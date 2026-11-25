// Package scanner contiene la tarea de escaneo antimalware (media.scan). La
// ejecuta la Cloud Function de segunda generación disparada por Pub/Sub; el
// worker de Cloud Run ya no la procesa.
package scanner

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/courses"
	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/queue"
	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/storage"
	"gorm.io/gorm"
)

// permanentError distingue un fallo que no se arregla reintentando (payload
// inválido, recurso eliminado) de uno transitorio (ClamAV, PostgreSQL, S3).
type permanentError struct{ err error }

func (e permanentError) Error() string { return e.err.Error() }
func (e permanentError) Unwrap() error { return e.err }

// Permanent marca un error como no reintentable: el disparador lo confirma.
func Permanent(err error) error { return permanentError{err: err} }

// IsPermanent indica si el error no debe reintentarse.
func IsPermanent(err error) bool {
	var p permanentError
	return errors.As(err, &p)
}

// ObjectStore es la parte de Cloud Storage que usa el escaneo.
type ObjectStore interface {
	DownloadToFile(bucket, objectKey, destPath string) error
	DeleteFile(bucket, objectKey string) error
}

// TranscodeQueue publica el transcode que sigue a un escaneo limpio.
type TranscodeQueue interface {
	EnqueueTranscode(ctx context.Context, p queue.TranscodePayload, idempotencyKey string) (string, error)
}

// Scan es una función de escaneo de archivo; la real habla con clamd por TCP.
type Scan func(host, filePath string) (infected bool, virus string, err error)

// Service ejecuta la tarea media.scan.
type Service struct {
	DB       *gorm.DB
	Store    ObjectStore
	Queue    TranscodeQueue
	ClamHost string
	// ScanFile es sustituible en pruebas; por defecto usa ScanFile (clamd).
	ScanFile Scan
}

// Handle verifica el original con ClamAV y, si está limpio y es multimedia,
// publica el transcode. Fail-closed: sin clamd devuelve un error transitorio y
// el disparador reintenta; nada infectado llega a publicarse.
//
// Es idempotente por el estado del recurso: una reentrega de un archivo ya
// limpio solo reencadena el transcode (que a su vez es idempotente) y una de
// uno infectado no hace nada; no vuelve a descargar ni a escanear.
func (s *Service) Handle(ctx context.Context, p queue.ScanPayload) error {
	if p.ResourceID == 0 || p.ObjectKey == "" {
		return Permanent(fmt.Errorf("payload incompleto"))
	}

	var r courses.Resource
	if err := s.DB.First(&r, p.ResourceID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return Permanent(fmt.Errorf("recurso %d no encontrado: %w", p.ResourceID, err))
		}
		return fmt.Errorf("leer recurso %d: %w", p.ResourceID, err)
	}

	switch r.ScanStatus {
	case courses.ScanClean:
		return s.enqueueTranscodeIfMedia(ctx, &r, p.TranscodeKey)
	case courses.ScanInfected:
		return nil
	}

	tmpDir, err := os.MkdirTemp("", fmt.Sprintf("scan-%d-", r.ID))
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmpDir)

	srcPath := filepath.Join(tmpDir, "original.bin")
	if err := s.Store.DownloadToFile(storage.BucketOriginals, p.ObjectKey, srcPath); err != nil {
		return fmt.Errorf("descarga original: %w", err)
	}

	scan := s.ScanFile
	if scan == nil {
		scan = ScanFile
	}
	infected, virus, err := scan(s.ClamHost, srcPath)
	if err != nil {
		return fmt.Errorf("clamav: %w", err)
	}
	if infected {
		// Cuarentena: el objeto se elimina, el recurso queda marcado.
		_ = s.Store.DeleteFile(storage.BucketOriginals, p.ObjectKey)
		if err := s.DB.Model(&r).Updates(map[string]interface{}{
			"scan_status":       courses.ScanInfected,
			"processing_status": courses.ProcessingFailed,
		}).Error; err != nil {
			return fmt.Errorf("persistir cuarentena: %w", err)
		}
		log.Printf("scanfn: recurso %d INFECTADO (%s), objeto eliminado", r.ID, virus)
		return nil
	}

	if err := s.DB.Model(&r).Update("scan_status", courses.ScanClean).Error; err != nil {
		return fmt.Errorf("persistir scan limpio: %w", err)
	}
	log.Printf("scanfn: recurso %d limpio, scan ok", r.ID)
	return s.enqueueTranscodeIfMedia(ctx, &r, p.TranscodeKey)
}

// MarkFailed deja el recurso como fallido cuando el evento ya no se puede
// reintentar (agotó su ventana). Equivale al dead-letter del worker.
func (s *Service) MarkFailed(id uint) error {
	if id == 0 {
		return nil
	}
	return s.DB.Model(&courses.Resource{}).Where("id = ?", id).Updates(map[string]interface{}{
		"processing_status": courses.ProcessingFailed,
		"scan_status":       courses.ScanFailed,
	}).Error
}

// enqueueTranscodeIfMedia encadena el transcode solo para video/audio.
// La reentrega del transcode es idempotente por el estado del recurso.
func (s *Service) enqueueTranscodeIfMedia(ctx context.Context, r *courses.Resource, transcodeKey string) error {
	if !courses.IsMediaType(r.Type) {
		return nil
	}
	if s.Queue == nil {
		return fmt.Errorf("publicador de Pub/Sub no configurado")
	}
	if transcodeKey == "" {
		transcodeKey = "transcode-" + r.StableID
	}
	_, err := s.Queue.EnqueueTranscode(ctx, queue.TranscodePayload{
		ResourceID:     r.ID,
		ObjectKey:      r.ObjectKey,
		MimeType:       r.MimeType,
		IdempotencyKey: transcodeKey,
	}, transcodeKey)
	return err
}
