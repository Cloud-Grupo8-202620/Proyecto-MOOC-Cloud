package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/courses"
	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/queue"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// maxPushBody acota el sobre de Pub/Sub. Los payloads de la aplicación son
// pequeños; el contenido multimedia viaja por Cloud Storage.
const maxPushBody = 1 << 20

// pushEnvelope es el formato JSON que Pub/Sub envía a una suscripción push.
type pushEnvelope struct {
	Message struct {
		Data            []byte            `json:"data"`
		Attributes      map[string]string `json:"attributes"`
		MessageID       string            `json:"messageId"`
		PublishTime     time.Time         `json:"publishTime"`
		DeliveryAttempt int               `json:"deliveryAttempt"`
	} `json:"message"`
	Subscription string `json:"subscription"`
}

// permanentError distingue un fallo que no se arregla reintentando (payload
// inválido, recurso eliminado) de uno transitorio (ClamAV, PostgreSQL, S3).
type permanentError struct{ err error }

func (e permanentError) Error() string { return e.err.Error() }
func (e permanentError) Unwrap() error { return e.err }

func permanent(err error) error { return permanentError{err: err} }

func isPermanent(err error) bool {
	var p permanentError
	return errors.As(err, &p)
}

// Handler monta los endpoints del worker: push de Pub/Sub, salud y métricas.
func (h *MediaHandler) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/pubsub/push", h.ServePush)
	mux.HandleFunc("/health", h.Health)
	mux.Handle("/metrics", promhttp.HandlerFor(jobs.registry, promhttp.HandlerOpts{
		ErrorHandling: promhttp.ContinueOnError,
	}))
	return mux
}

// Health responde a la sonda de arranque de Cloud Run. El worker no usa Redis:
// su dependencia obligatoria es PostgreSQL; ClamAV y Storage se reintentan por
// tarea para no impedir que la instancia arranque por una caída temporal.
func (h *MediaHandler) Health(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	sqlDB, err := h.DB.DB()
	if err != nil || sqlDB.PingContext(ctx) != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		_, _ = w.Write([]byte(`{"status":"error","message":"PostgreSQL no responde"}`))
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"status":"ok","service":"worker"}`))
}

// ServePush ejecuta una entrega de Pub/Sub y solo responde 2xx después de
// persistir el estado/resultado. Un 5xx deja el mensaje sin confirmar para que
// Pub/Sub lo reentregue; los errores permanentes se confirman para no crear un
// bucle infinito y acaban diagnosticados en el log.
func (h *MediaHandler) ServePush(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	var env pushEnvelope
	r.Body = http.MaxBytesReader(w, r.Body, maxPushBody)
	if err := json.NewDecoder(r.Body).Decode(&env); err != nil {
		log.Printf("worker: push inválido: %v", err)
		w.WriteHeader(http.StatusNoContent)
		return
	}
	msg := env.Message
	if len(msg.Data) == 0 {
		log.Printf("worker: push sin datos message_id=%s", msg.MessageID)
		w.WriteHeader(http.StatusNoContent)
		return
	}
	taskType := msg.Attributes["type"]
	if taskType == "" {
		log.Printf("worker: push sin tipo message_id=%s", msg.MessageID)
		w.WriteHeader(http.StatusNoContent)
		return
	}

	timeout := h.TranscodeTimeout
	if timeout <= 0 {
		timeout = 9 * time.Minute
	}
	ctx, cancel := context.WithTimeout(r.Context(), timeout+30*time.Second)
	defer cancel()

	jobs.JobStarted()
	var err error
	defer func() { jobs.JobFinished(err) }()

	var resourceID uint
	switch taskType {
	case queue.TypeMediaTranscode:
		var p queue.TranscodePayload
		p, err = queue.Decode[queue.TranscodePayload](msg.Data)
		if err != nil {
			log.Printf("worker: transcode payload inválido message_id=%s: %v", msg.MessageID, err)
			w.WriteHeader(http.StatusNoContent)
			return
		}
		resourceID = p.ResourceID
		log.Printf("worker: transcode recibido message_id=%s attempt=%d resource=%d", msg.MessageID, msg.DeliveryAttempt, p.ResourceID)
		err = h.HandleTranscode(ctx, p)
	default:
		log.Printf("worker: tipo desconocido %q message_id=%s", taskType, msg.MessageID)
		w.WriteHeader(http.StatusNoContent)
		return
	}

	if err == nil {
		log.Printf("worker: tarea completada message_id=%s type=%s resource=%d", msg.MessageID, taskType, resourceID)
		w.WriteHeader(http.StatusNoContent)
		return
	}

	log.Printf("worker: tarea falló message_id=%s type=%s resource=%d attempt=%d err=%v", msg.MessageID, taskType, resourceID, msg.DeliveryAttempt, err)
	if isPermanent(err) {
		log.Printf("worker: error permanente confirmado message_id=%s", msg.MessageID)
		w.WriteHeader(http.StatusNoContent)
		return
	}
	maxAttempts := h.MaxAttempts
	if maxAttempts <= 0 {
		maxAttempts = 5
	}
	if msg.DeliveryAttempt > 0 && msg.DeliveryAttempt >= maxAttempts {
		h.markFailedByID(resourceID, taskType, fmt.Sprintf("agotó %d intentos: %v", maxAttempts, err))
		log.Printf("worker: sin reintentos message_id=%s resource=%d; se deja para dead-letter", msg.MessageID, resourceID)
	}
	w.WriteHeader(http.StatusInternalServerError)
}

func (h *MediaHandler) markFailedByID(id uint, taskType, detail string) {
	if id == 0 {
		return
	}
	log.Printf("worker: recurso %d fallo definitivo (%s): %s", id, taskType, detail)
	updates := map[string]interface{}{"processing_status": courses.ProcessingFailed}
	if err := h.DB.Model(&courses.Resource{}).Where("id = ?", id).Updates(updates).Error; err != nil {
		log.Printf("worker: recurso %d no se pudo persistir el fallo: %v", id, err)
	}
}
