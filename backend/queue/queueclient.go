package queue

import (
	"context"
	"encoding/json"
	"errors"
	"os"

	"cloud.google.com/go/pubsub/v2"
	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/utils"
)

// Client publica trabajos en un topic de Pub/Sub. El worker los recibe por una
// suscripción push autenticada; no hay consumidor en este proceso.
type Client struct {
	client    *pubsub.Client
	publisher *pubsub.Publisher
}

// NewClient construye el publicador desde variables de entorno. En local,
// PUBSUB_EMULATOR_HOST hace que el SDK hable con el emulador sin credenciales.
func NewClient(ctx context.Context) (*Client, error) {
	projectID := utils.GetEnv("PUBSUB_PROJECT_ID", os.Getenv("GOOGLE_CLOUD_PROJECT"))
	if projectID == "" {
		return nil, errors.New("PUBSUB_PROJECT_ID no está definido")
	}
	topicID := utils.GetEnv("PUBSUB_TOPIC", "media-jobs")
	client, err := pubsub.NewClient(ctx, projectID)
	if err != nil {
		return nil, err
	}
	return &Client{client: client, publisher: client.Publisher(topicID)}, nil
}

// Close libera el publicador y sus conexiones.
func (c *Client) Close() error {
	if c == nil {
		return nil
	}
	if c.publisher != nil {
		c.publisher.Stop()
	}
	if c.client != nil {
		return c.client.Close()
	}
	return nil
}

// enqueue publica un trabajo. El message_id que devuelve Pub/Sub es el
// identificador que se registra y se muestra como task_id.
func (c *Client) enqueue(ctx context.Context, taskType string, payload interface{}, idempotencyKey string) (string, error) {
	if c == nil || c.publisher == nil {
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
	result := c.publisher.Publish(ctx, &pubsub.Message{Data: data, Attributes: attributes})
	return result.Get(ctx)
}

// EnqueueTranscode publica un trabajo de transcodificación HLS.
func (c *Client) EnqueueTranscode(ctx context.Context, p TranscodePayload, idempotencyKey string) (string, error) {
	if idempotencyKey == "" {
		idempotencyKey = p.IdempotencyKey
	}
	return c.enqueue(ctx, TypeMediaTranscode, p, idempotencyKey)
}

// EnqueueScan publica un trabajo de escaneo antimalware (fail-closed).
func (c *Client) EnqueueScan(ctx context.Context, p ScanPayload, idempotencyKey string) (string, error) {
	return c.enqueue(ctx, TypeMediaScan, p, idempotencyKey)
}
