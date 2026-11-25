package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/courses"
	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/queue"
	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/storage"
	"gorm.io/gorm"
)

// ffmpegBinary es una ruta absoluta para no depender de PATH en el contenedor.
const ffmpegBinary = "/usr/bin/ffmpeg"

// MediaHandler procesa multimedia a HLS de forma idempotente,
// El escaneo antimalware previo (fail-closed) lo ejecuta la Cloud Function y
// el transcode solo se publica una vez que el recurso está limpio.
type MediaHandler struct {
	DB               *gorm.DB
	Store            *storage.Client
	MaxAttempts      int
	TranscodeTimeout time.Duration
}

// HandleTranscode descarga el original, genera HLS sin upscaling y conserva el original.
func (h *MediaHandler) HandleTranscode(ctx context.Context, p queue.TranscodePayload) error {
	if p.ResourceID == 0 || p.ObjectKey == "" {
		return permanent(fmt.Errorf("payload incompleto"))
	}

	var r courses.Resource
	if err := h.DB.First(&r, p.ResourceID).Error; err != nil {
		return permanent(fmt.Errorf("recurso %d no encontrado: %w", p.ResourceID, err))
	}

	// Idempotencia: doble entrega no genera salidas repetidas.
	if r.ProcessingStatus == courses.ProcessingReady && r.HLSKey != "" {
		log.Printf("worker: recurso %d ya procesado (idempotente), skip", r.ID)
		return nil
	}
	// Otra entrega puede estar ejecutando ffmpeg. Se devuelve un error para que
	// Pub/Sub reintente más tarde; si el proceso murió, la marca de tiempo deja
	// reclamar el trabajo tras el margen.
	if r.ProcessingStatus == courses.ProcessingProcessing && time.Since(r.UpdatedAt) < 12*time.Minute {
		return fmt.Errorf("recurso %d ya está en procesamiento", r.ID)
	}

	if err := h.DB.Model(&r).Updates(map[string]interface{}{"processing_status": courses.ProcessingProcessing}).Error; err != nil {
		return fmt.Errorf("persistir inicio de transcode: %w", err)
	}

	tmpDir, err := os.MkdirTemp("", fmt.Sprintf("transcode-%d-", r.ID))
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmpDir)

	ext := filepath.Ext(p.ObjectKey)
	if ext == "" {
		ext = ".bin"
	}
	srcPath := filepath.Join(tmpDir, "original"+ext)
	if err := h.Store.DownloadToFile(storage.BucketOriginals, p.ObjectKey, srcPath); err != nil {
		h.markFailed(&r, fmt.Sprintf("descarga: %v", err))
		return fmt.Errorf("descarga original: %w", err)
	}

	outDir := filepath.Join(tmpDir, "hls")
	if err := os.MkdirAll(outDir, 0755); err != nil {
		return err
	}
	playlist := filepath.Join(outDir, "index.m3u8")

	args := []string{"-y", "-i", srcPath}
	if isAudio := strings.Contains(strings.ToLower(r.MimeType), "audio") || r.Type == courses.ResourceTypeAudio; !isAudio {
		// Video a HLS 720p máximo, sin upscaling, conserva aspecto.
		args = append(args, "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
			"-vf", "scale=w=-2:h='min(ih,720)'")
	}
	args = append(args, "-c:a", "aac", "-b:a", "128k",
		"-hls_time", "6", "-hls_playlist_type", "vod",
		"-hls_segment_filename", filepath.Join(outDir, "seg%03d.ts"),
		playlist)

	timeout := h.TranscodeTimeout
	if timeout <= 0 {
		timeout = 9 * time.Minute
	}
	cmdCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	cmd := exec.CommandContext(cmdCtx, ffmpegBinary, args...)
	// ffmpeg es lo que satura los vCPU del worker, así que su concurrencia
	// real es la métrica que explica la cola del escenario de carga multimedia.
	jobs.FFmpegStarted()
	defer jobs.FFmpegFinished()
	out, err := cmd.CombinedOutput()
	if err != nil {
		h.markFailed(&r, fmt.Sprintf("ffmpeg: %v %.500s", err, string(out)))
		return fmt.Errorf("ffmpeg: %w output=%.500s", err, string(out))
	}

	prefix := fmt.Sprintf("%s/", r.StableID)
	entries, err := os.ReadDir(outDir)
	if err != nil {
		return err
	}
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		local := filepath.Join(outDir, e.Name())
		ct := "video/MP2T"
		if strings.HasSuffix(e.Name(), ".m3u8") {
			ct = "application/vnd.apple.mpegurl"
		}
		if err := h.Store.UploadFile(storage.BucketHLS, prefix+e.Name(), local, ct); err != nil {
			h.markFailed(&r, fmt.Sprintf("subida hls: %v", err))
			return fmt.Errorf("subida %s: %w", e.Name(), err)
		}
	}

	// Original se conserva intacto en BucketOriginals; solo se registra el derivado.
	if err := h.DB.Model(&r).Updates(map[string]interface{}{
		"processing_status": courses.ProcessingReady,
		"hls_key":           prefix + "index.m3u8",
	}).Error; err != nil {
		return fmt.Errorf("persistir HLS listo: %w", err)
	}
	log.Printf("worker: recurso %d HLS listo en %s", r.ID, prefix+"index.m3u8")
	return nil
}

func (h *MediaHandler) markFailed(r *courses.Resource, detail string) {
	log.Printf("worker: recurso %d fallo: %s", r.ID, detail)
	if err := h.DB.Model(r).Update("processing_status", courses.ProcessingFailed).Error; err != nil {
		log.Printf("worker: recurso %d no se pudo marcar failed: %v", r.ID, err)
	}
}
