// Command local ejecuta ScanMedia fuera de Google Cloud, solo para desarrollo
// con docker compose. El emulador de Pub/Sub entrega un sobre "push"; este
// adaptador lo convierte en el CloudEvent que Eventarc entrega en producción y
// llama a la misma función, de modo que no hay una segunda implementación.
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/functions/scanfn"
	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/utils"
	"github.com/cloudevents/sdk-go/v2/event"
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) { _, _ = w.Write([]byte("ok")) })
	mux.HandleFunc("/pubsub/push", func(w http.ResponseWriter, r *http.Request) {
		var env struct {
			Message struct {
				Data        []byte            `json:"data"`
				Attributes  map[string]string `json:"attributes"`
				MessageID   string            `json:"messageId"`
				PublishTime time.Time         `json:"publishTime"`
			} `json:"message"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&env); err != nil {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		e := event.New()
		e.SetID(env.Message.MessageID)
		e.SetType("google.cloud.pubsub.topic.v1.messagePublished")
		e.SetSource("//pubsub.googleapis.com/local")
		if err := e.SetData(event.ApplicationJSON, map[string]any{"message": env.Message}); err != nil {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		if err := scanfn.ScanMedia(r.Context(), e); err != nil {
			w.WriteHeader(http.StatusInternalServerError) // el emulador reentrega
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})
	addr := ":" + utils.GetEnv("PORT", "8080")
	log.Printf("scanfn local: escuchando en %s", addr)
	log.Fatal((&http.Server{Addr: addr, Handler: mux, ReadHeaderTimeout: 10 * time.Second}).ListenAndServe())
}
