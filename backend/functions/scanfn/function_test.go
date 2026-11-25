package scanfn

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/cloudevents/sdk-go/v2/event"
)

func evento(t *testing.T, data messagePublishedData) event.Event {
	t.Helper()
	e := event.New()
	e.SetID("e1")
	e.SetType("google.cloud.pubsub.topic.v1.messagePublished")
	e.SetSource("//pubsub.googleapis.com/projects/p/topics/t")
	if err := e.SetData(event.ApplicationJSON, data); err != nil {
		t.Fatal(err)
	}
	return e
}

// Los mensajes que nunca podrán procesarse se confirman (nil) sin tocar la base
// de datos: devolver error provocaría reintentos inútiles hasta agotar la
// retención del topic.
func TestMensajesInvalidosSeConfirman(t *testing.T) {
	var ajeno, sinPayload messagePublishedData
	ajeno.Message.Attributes = map[string]string{"type": "media.transcode"}
	sinPayload.Message.Attributes = map[string]string{"type": "media.scan"}
	sinPayload.Message.Data = []byte("no es json")

	for name, d := range map[string]messagePublishedData{"tipo ajeno": ajeno, "payload inválido": sinPayload} {
		if err := ScanMedia(context.Background(), evento(t, d)); err != nil {
			t.Errorf("%s: se esperaba nil, llegó %v", name, err)
		}
	}
}

func TestEventoSinCuerpoSeConfirma(t *testing.T) {
	e := event.New()
	e.SetID("e2")
	e.SetType("x")
	e.SetSource("s")
	_ = e.SetData(event.ApplicationJSON, json.RawMessage(`"texto"`))
	if err := ScanMedia(context.Background(), e); err != nil {
		t.Fatalf("se esperaba nil, llegó %v", err)
	}
}
