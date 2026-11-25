package queue

import (
	"context"
	"encoding/json"
	"errors"
	"os"

	"cloud.google.com/go/pubsub/v2"
	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/utils"
)

// Client publica trabajos en Pub/Sub. El transcode viaja por el topic de media
// y lo recibe el worker por una suscripción push autenticada; el escaneo viaja
// por su propio topic y lo ejecuta la Cloud Function. No hay consumidor en este
// proceso.
type Client struct {
	client        *pubsub.Client
	publisher     *pubsub.Publisher
	scanPublisher *pubsub.Publisher
}

// NewClient construye el publicador desde variables de entorno. En local,
// PUBSUB_EMULATOR_HOST hace que el SDK hable con el emulador sin credenciales.
func NewClient(ctx context.Context) (*Client, error) {
	projectID := utils.GetEnv("PUBSUB_PROJECT_ID", os.Getenv("GOOGLE_CLOUD_PROJECT"))
	if projectID == "" {
		return nil, errors.New("PUBSUB_PROJECT_ID no está definido")
	}
	topicID := utils.GetEnv("PUBSUB_TOPIC", "media-jobs")
	scanTopicID := utils.GetEnv("PUBSUB_SCAN_TOPIC", "media-scan")
	client, err := pubsub.NewClient(ctx, projectID)
	if err != nil {
		return nil, err
	}
	return &Client{
		client:        client,
		publisher:     client.Publisher(topicID),
		scanPublisher: client.Publisher(scanTopicID),
	}, nil
}

// Close libera el publicador y sus conexiones.
func (c *Client) Close() error {
	if c == nil {
		return nil
	}
	if c.publisher != nil {
		c.publisher.Stop()
	}
	if c.scanPublisher != nil {
		c.scanPublisher.Stop()
	}
	if c.client != nil {
		return c.client.Close()
	}
	return nil
}

// enqueue publica un trabajo. El message_id que devuelve Pub/Sub es el
// identificador que se registra y se muestra como task_id.
func (c *Client) enqueue(ctx context.Context, publisher *pubsub.Publisher, taskType string, payload interface{}, idempotencyKey string) (string, error) {
	if c == nil || publisher == nil {
		return "", errors.New("publicador de Pub/Sub no configurado")
	}
	data, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	attributes := map[string]string{"type": taskType}
	if idempotencyKey != "" {
		attributes["idempotency_key"] = idempotencyKey
	}
	result := publisher.Publish(ctx, &pubsub.Message{Data: data, Attributes: attributes})
	return result.Get(ctx)
}

// EnqueueTranscode publica un trabajo de transcodificación HLS.
func (c *Client) EnqueueTranscode(ctx context.Context, p TranscodePayload, idempotencyKey string) (string, error) {
	if idempotencyKey == "" {
		idempotencyKey = p.IdempotencyKey
	}
	return c.enqueue(ctx, c.publisher, TypeMediaTranscode, p, idempotencyKey)
}

// EnqueueScan publica un trabajo de escaneo antimalware (fail-closed) en el
// topic de escaneo, que activa la Cloud Function.
func (c *Client) EnqueueScan(ctx context.Context, p ScanPayload, idempotencyKey string) (string, error) {
	return c.enqueue(ctx, c.scanPublisher, TypeMediaScan, p, idempotencyKey)
}
