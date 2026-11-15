package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// Un tipo desconocido no debe dejar el mensaje en reintento eterno: se
// confirma y queda en el log. La prueba no necesita base de datos.
func TestServePushConfirmaTipoDesconocido(t *testing.T) {
	h := &MediaHandler{}
	body := `{"message":{"data":"e30=","attributes":{"type":"desconocido"},"messageId":"m1"}}`
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/pubsub/push", strings.NewReader(body))
	h.ServePush(rec, req)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("código = %d, se esperaba 204", rec.Code)
	}
}

func TestServePushConfirmaSobreInvalido(t *testing.T) {
	h := &MediaHandler{}
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/pubsub/push", strings.NewReader("{"))
	h.ServePush(rec, req)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("código = %d, se esperaba 204", rec.Code)
	}
}

func TestPushEnvelopeDecodificaBase64(t *testing.T) {
	var env pushEnvelope
	if err := json.Unmarshal([]byte(`{"message":{"data":"e30=","attributes":{"type":"media.scan"},"messageId":"m1"}}`), &env); err != nil {
		t.Fatalf("json: %v", err)
	}
	if string(env.Message.Data) != "{}" || env.Message.Attributes["type"] != "media.scan" {
		t.Fatalf("sobre inesperado: %+v", env.Message)
	}
}

func TestErrorPermanenteSeReconoce(t *testing.T) {
	err := permanent(errors.New("recurso no encontrado"))
	if !isPermanent(err) {
		t.Fatal("un error permanente debe reconocerse")
	}
	if isPermanent(errors.New("clamav no responde")) {
		t.Fatal("un error transitorio no debe tratarse como permanente")
	}
}
