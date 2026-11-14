package main

import (
	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/telemetry"
	"github.com/prometheus/client_golang/prometheus"
)

// jobMetrics son los contadores de trabajo del worker. Se publican en /metrics
// para depuración local; en Cloud Run la evidencia de escalamiento sale de las
// métricas administradas de Cloud Run y Pub/Sub.
type jobMetrics struct {
	registry *prometheus.Registry
	active   prometheus.Gauge
	ffmpeg   prometheus.Gauge
	done     prometheus.Counter
	failed   prometheus.Counter
}

// jobs es el registro de telemetría del worker. Se construye al arrancar el
// paquete para que ningún manejador tenga que comprobar si ya existe.
var jobs = newJobMetrics()

func newJobMetrics() *jobMetrics {
	registry, labeled := telemetry.NewRegistry(telemetry.ComponentWorker)
	j := &jobMetrics{
		registry: registry,
		active: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "mooc_worker_jobs_active",
			Help: "Trabajos de media en ejecución ahora mismo en el worker.",
		}),
		ffmpeg: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "mooc_worker_ffmpeg_active",
			Help: "Procesos ffmpeg simultáneos en el worker.",
		}),
		done: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "mooc_worker_jobs_completed_total",
			Help: "Trabajos de media completados correctamente desde el arranque.",
		}),
		failed: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "mooc_worker_jobs_failed_total",
			Help: "Ejecuciones que terminaron en error, incluidas las que se van a reintentar.",
		}),
	}
	labeled.MustRegister(j.active, j.ffmpeg, j.done, j.failed)
	return j
}

// JobStarted marca el inicio de un trabajo de media.
func (j *jobMetrics) JobStarted() { j.active.Inc() }

// JobFinished cierra el trabajo y contabiliza el resultado.
func (j *jobMetrics) JobFinished(err error) {
	j.active.Dec()
	if err != nil {
		j.failed.Inc()
		return
	}
	j.done.Inc()
}

// FFmpegStarted marca el arranque de un proceso ffmpeg.
func (j *jobMetrics) FFmpegStarted() { j.ffmpeg.Inc() }

// FFmpegFinished marca la salida de un proceso ffmpeg.
func (j *jobMetrics) FFmpegFinished() { j.ffmpeg.Dec() }
