// Package scanfn es la Cloud Function (segunda generación) que ejecuta la tarea
// media.scan. Eventarc la activa con cada mensaje del topic de escaneo; la
// entrega es "al menos una vez", así que todo el flujo es idempotente.
package scanfn

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/queue"
	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/scanner"
	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/storage"
	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/utils"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"github.com/cloudevents/sdk-go/v2/event"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

// EntryPoint es el nombre con el que Terraform registra la función.
const EntryPoint = "ScanMedia"

func init() {
	functions.CloudEvent(EntryPoint, ScanMedia)
}

// messagePublishedData es el cuerpo del evento
// google.cloud.pubsub.topic.v1.messagePublished.
type messagePublishedData struct {
	Message struct {
		Data        []byte            `json:"data"`
		Attributes  map[string]string `json:"attributes"`
		MessageID   string            `json:"messageId"`
		PublishTime time.Time         `json:"publishTime"`
	} `json:"message"`
}

var (
	once    sync.Once
	svc     *scanner.Service
	initErr error
)

// service construye una vez por instancia las conexiones a Cloud SQL, Cloud
// Storage y Pub/Sub; las invocaciones siguientes las reutilizan.
func service(ctx context.Context) (*scanner.Service, error) {
	once.Do(func() {
		db, err := gorm.Open(postgres.Open(utils.GetPostgresDSN()), &gorm.Config{})
		if err != nil {
			initErr = fmt.Errorf("postgres: %w", err)
			return
		}
		sqlDB, err := db.DB()
		if err != nil {
			initErr = fmt.Errorf("pool postgres: %w", err)
			return
		}
		maxConns := utils.GetEnvInt("POSTGRES_MAX_OPEN_CONNS", 1)
		sqlDB.SetMaxOpenConns(maxConns)
		sqlDB.SetMaxIdleConns(maxConns)
		sqlDB.SetConnMaxLifetime(5 * time.Minute)

		store, err := storage.NewClient()
		if err != nil {
			initErr = fmt.Errorf("storage: %w", err)
			return
		}
		qc, err := queue.NewClient(context.Background())
		if err != nil {
			initErr = fmt.Errorf("pubsub: %w", err)
			return
		}
		svc = &scanner.Service{
			DB:       db,
			Store:    store,
			Queue:    qc,
			ClamHost: utils.GetEnv("CLAMAV_HOST", "clamav:3310"),
		}
	})
	return svc, initErr
}

// ScanMedia procesa un mensaje del topic de escaneo.
//
// Contrato de reintentos (retry_policy = RETRY): devolver error provoca una
// reentrega; devolver nil confirma el mensaje. Los fallos permanentes y los
// eventos que agotaron su ventana se confirman para no entrar en un bucle.
func ScanMedia(ctx context.Context, e event.Event) error {
	var data messagePublishedData
	if err := e.DataAs(&data); err != nil {
		log.Printf("scanfn: evento inválido id=%s: %v", e.ID(), err)
		return nil
	}
	msg := data.Message
	if msg.Attributes["type"] != queue.TypeMediaScan {
		log.Printf("scanfn: tipo ignorado %q message_id=%s", msg.Attributes["type"], msg.MessageID)
		return nil
	}
	payload, err := queue.Decode[queue.ScanPayload](msg.Data)
	if err != nil {
		log.Printf("scanfn: payload inválido message_id=%s: %v", msg.MessageID, err)
		return nil
	}

	s, err := service(ctx)
	if err != nil {
		// Falla de arranque (p. ej. Cloud SQL inaccesible): es transitoria, pero
		// sync.Once no reintenta; se sale de la instancia para reconstruirla.
		log.Printf("scanfn: servicio no disponible: %v", err)
		return err
	}
	return process(ctx, s, payload, msg.MessageID, msg.PublishTime)
}

// process aplica la política de reintentos sobre un servicio ya construido.
func process(ctx context.Context, s *scanner.Service, p queue.ScanPayload, messageID string, published time.Time) error {
	maxAge := utils.GetEnvDuration("SCAN_MAX_EVENT_AGE", time.Hour)
	log.Printf("scanfn: scan recibido message_id=%s resource=%d", messageID, p.ResourceID)

	err := s.Handle(ctx, p)
	switch {
	case err == nil:
		log.Printf("scanfn: tarea completada message_id=%s resource=%d", messageID, p.ResourceID)
		return nil
	case scanner.IsPermanent(err):
		log.Printf("scanfn: error permanente confirmado message_id=%s: %v", messageID, err)
		return nil
	case !published.IsZero() && maxAge > 0 && time.Since(published) > maxAge:
		log.Printf("scanfn: sin reintentos message_id=%s resource=%d tras %s: %v", messageID, p.ResourceID, maxAge, err)
		if merr := s.MarkFailed(p.ResourceID); merr != nil {
			log.Printf("scanfn: no se pudo marcar fallo resource=%d: %v", p.ResourceID, merr)
			return merr
		}
		return nil
	default:
		log.Printf("scanfn: tarea falló message_id=%s resource=%d, se reintenta: %v", messageID, p.ResourceID, err)
		return err
	}
}
