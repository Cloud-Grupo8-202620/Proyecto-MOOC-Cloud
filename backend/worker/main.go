package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/courses"
	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/storage"
	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/utils"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

func main() {
	dsn := utils.GetPostgresDSN()
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatalf("worker: no se pudo conectar a Postgres: %v", err)
	}
	// Tope bajo: el worker compite por las mismas conexiones de Cloud SQL que
	// la API y solo necesita una por trabajo concurrente en vuelo. Con varias
	// réplicas lo fija el despliegue (POSTGRES_MAX_OPEN_CONNS).
	sqlDB, err := db.DB()
	if err != nil {
		log.Fatalf("worker: no se pudo obtener el pool de Postgres: %v", err)
	}
	maxConns := utils.GetEnvInt("POSTGRES_MAX_OPEN_CONNS", 2)
	sqlDB.SetMaxOpenConns(maxConns)
	sqlDB.SetMaxIdleConns(maxConns)
	sqlDB.SetConnMaxLifetime(5 * time.Minute)
	// Migración compartida con la API (misma fuente de verdad) y con el mismo
	// lock: una API y un worker que arrancan juntos migran por turnos.
	if err := utils.MigrateWithLock(db,
		&courses.Course{},
		&courses.CourseVersion{},
		&courses.Module{},
		&courses.Unit{},
		&courses.Resource{},
		&courses.Matricula{},
	); err != nil {
		log.Fatalf("worker: no se pudo migrar: %v", err)
	}

	store, err := storage.NewClient()
	if err != nil {
		log.Fatalf("worker: no se pudo crear cliente S3: %v", err)
	}

	h := &MediaHandler{
		DB:               db,
		Store:            store,
		MaxAttempts:      utils.GetEnvInt("WORKER_MAX_ATTEMPTS", 5),
		TranscodeTimeout: utils.GetEnvDuration("WORKER_TRANSCODE_TIMEOUT", 9*time.Minute),
	}

	port := utils.GetEnv("PORT", "8080")
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           h.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
	}
	go func() {
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("worker: %v", err)
		}
	}()
	log.Printf("worker: %s escuchando en %s (push de Pub/Sub)", utils.InstanceName(), srv.Addr)

	// Cloud Run concede unos segundos tras SIGTERM. Si una tarea no termina en
	// este margen, el proceso sale sin confirmar el mensaje y Pub/Sub lo
	// reentrega; la idempotencia del recurso evita efectos duplicados.
	sigCtx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()
	<-sigCtx.Done()

	timeout := utils.GetEnvDuration("WORKER_SHUTDOWN_TIMEOUT", 8*time.Second)
	shutdownCtx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("worker: apagado forzado: %v", err)
		return
	}
	log.Print("worker: apagado ordenado completo")
}
