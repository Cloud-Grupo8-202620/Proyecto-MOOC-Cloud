variable "project_id" {
  description = "Proyecto de Google Cloud donde se despliega la entrega 4"
  type        = string
}

variable "region" {
  description = "Región de Cloud Run, Cloud SQL, Memorystore, Storage y Artifact Registry"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zona de la VM de soporte (ClamAV y Mailpit) y de Memorystore Basic"
  type        = string
  default     = "us-central1-a"
}

variable "name_prefix" {
  description = "Prefijo de todos los recursos. mooc4 evita colisiones con el state de entrega 3"
  type        = string
  default     = "mooc4"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.name_prefix))
    error_message = "name_prefix debe ser minúsculas (letras, dígitos o guiones) y comenzar por letra."
  }
}

variable "image_tag" {
  description = "Etiqueta publicada en Artifact Registry por scripts/publish_images.sh"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Cloud Run: límites de los tres servicios
# ---------------------------------------------------------------------------

variable "frontend_min_instances" {
  description = "Mínimo de instancias del frontend (0 permite scale-to-zero)"
  type        = number
  default     = 0
}

variable "frontend_max_instances" {
  description = "Máximo de instancias del frontend; el enunciado exige 3"
  type        = number
  default     = 3

  validation {
    condition     = var.frontend_max_instances >= var.frontend_min_instances && var.frontend_max_instances <= 3
    error_message = "El frontend debe escalar como máximo a 3 instancias y el mínimo no puede superarlo."
  }
}

variable "backend_min_instances" {
  description = "Mínimo de instancias del backend; 0 permite scale-to-zero"
  type        = number
  default     = 0
}

variable "backend_max_instances" {
  description = "Máximo de instancias del backend; el enunciado exige 3"
  type        = number
  default     = 3

  validation {
    condition     = var.backend_max_instances >= var.backend_min_instances && var.backend_max_instances <= 3
    error_message = "El backend debe escalar como máximo a 3 instancias y el mínimo no puede superarlo."
  }
}

variable "worker_min_instances" {
  description = "Mínimo de instancias del worker (0 permite scale-to-zero entre mensajes)"
  type        = number
  default     = 0
}

variable "worker_max_instances" {
  description = "Máximo de instancias del worker; el enunciado exige 3"
  type        = number
  default     = 3

  validation {
    condition     = var.worker_max_instances >= var.worker_min_instances && var.worker_max_instances <= 3
    error_message = "El worker debe escalar como máximo a 3 instancias y el mínimo no puede superarlo."
  }
}

variable "frontend_concurrency" {
  description = "Solicitudes simultáneas por instancia del frontend"
  type        = number
  default     = 5
}

variable "backend_concurrency" {
  description = "Solicitudes simultáneas por instancia del backend"
  type        = number
  default     = 10
}

variable "worker_concurrency" {
  description = "Solicitudes push simultáneas por instancia del worker (1 ffmpeg por instancia)"
  type        = number
  default     = 1
}

# ---------------------------------------------------------------------------
# Base de datos y sesiones
# ---------------------------------------------------------------------------

variable "db_tier" {
  description = "Tier de Cloud SQL. db-f1-micro admite 25 conexiones"
  type        = string
  default     = "db-f1-micro"
}

variable "db_name" {
  description = "Nombre de la base de datos"
  type        = string
  default     = "mydb"
}

variable "db_user" {
  description = "Usuario administrador de PostgreSQL"
  type        = string
  default     = "postgres"
}

variable "db_max_connections" {
  description = "Conexiones máximas del tier de Cloud SQL"
  type        = number
  default     = 25
}

variable "backend_db_max_open_conns" {
  description = "Pool de PostgreSQL por instancia del backend"
  type        = number
  default     = 4
}

variable "worker_db_max_open_conns" {
  description = "Pool de PostgreSQL por instancia del worker"
  type        = number
  default     = 2

  validation {
    condition = (
      var.backend_max_instances * var.backend_db_max_open_conns +
      var.worker_max_instances * var.worker_db_max_open_conns +
      var.scan_fn_max_instances * var.scan_fn_db_max_open_conns +
      3 <= var.db_max_connections
    )
    error_message = "Los pools de backend, worker y función en su máximo, más 3 conexiones reservadas, superan db_max_connections."
  }
}

variable "redis_memory_gb" {
  description = "Tamaño de Memorystore para sesiones, códigos y locks TUS"
  type        = number
  default     = 1
}

variable "redis_version" {
  description = "Versión de Memorystore Redis"
  type        = string
  default     = "REDIS_7_0"
}

variable "support_machine_type" {
  description = "VM de soporte para ClamAV y Mailpit (fuera de Cloud Run)"
  type        = string
  default     = "e2-medium"
}

variable "support_internal_ip" {
  description = "IP interna fija de la VM de soporte"
  type        = string
  default     = "10.10.1.30"
}

# ---------------------------------------------------------------------------
# Pub/Sub y aplicación
# ---------------------------------------------------------------------------

variable "pubsub_ack_deadline_seconds" {
  description = "Ack deadline de la suscripción push (máximo 600)"
  type        = number
  default     = 600

  validation {
    condition     = var.pubsub_ack_deadline_seconds >= 10 && var.pubsub_ack_deadline_seconds <= 600
    error_message = "El ack deadline de Pub/Sub debe estar entre 10 y 600 segundos."
  }
}

variable "pubsub_max_delivery_attempts" {
  description = "Intentos antes de enviar al dead-letter topic (mínimo 5)"
  type        = number
  default     = 5

  validation {
    condition     = var.pubsub_max_delivery_attempts >= 5 && var.pubsub_max_delivery_attempts <= 100
    error_message = "Pub/Sub exige entre 5 y 100 intentos para el dead-letter."
  }
}

variable "worker_transcode_timeout" {
  description = "Tope de ffmpeg por tarea; debe quedar por debajo del ack deadline"
  type        = string
  default     = "9m"
}

variable "cors_origins" {
  description = "Orígenes CORS de los buckets. * es aceptable: las URLs firmadas autorizan la operación"
  type        = list(string)
  default     = ["*"]
}

variable "admin_username" {
  description = "Usuario administrador inicial creado por el Cloud Run Job"
  type        = string
  default     = "admin"
}

variable "admin_email" {
  description = "Correo del administrador inicial"
  type        = string
  default     = "admin@example.com"
}

# ---------------------------------------------------------------------------
# Cloud Function media.scan (entrega 5)
# ---------------------------------------------------------------------------

variable "scan_fn_runtime" {
  description = "Runtime de Cloud Run functions; debe cubrir la versión de go.mod de backend/"
  type        = string
  default     = "go126"
}

variable "scan_fn_memory" {
  description = "Memoria de la función (descarga el original a /tmp, que cuenta como memoria)"
  type        = string
  default     = "1Gi"
}

variable "scan_fn_timeout_seconds" {
  description = "Tiempo máximo por invocación de la función (hasta 3600 en eventos)"
  type        = number
  default     = 540

  validation {
    condition     = var.scan_fn_timeout_seconds >= 60 && var.scan_fn_timeout_seconds <= 3600
    error_message = "El timeout de la función debe estar entre 60 y 3600 segundos."
  }
}

variable "scan_fn_min_instances" {
  description = "Mínimo de instancias de la función (0 permite scale-to-zero)"
  type        = number
  default     = 0
}

variable "scan_fn_max_instances" {
  description = "Máximo de instancias de la función; limita las conexiones a Cloud SQL"
  type        = number
  default     = 3

  validation {
    condition     = var.scan_fn_max_instances >= var.scan_fn_min_instances && var.scan_fn_max_instances <= 3
    error_message = "La función debe escalar como máximo a 3 instancias y el mínimo no puede superarlo."
  }
}

variable "scan_fn_db_max_open_conns" {
  description = "Pool de PostgreSQL por instancia de la función (concurrencia 1)"
  type        = number
  default     = 1
}

variable "scan_fn_max_event_age" {
  description = "Edad máxima de un mensaje de escaneo antes de marcar el recurso como fallido y confirmarlo"
  type        = string
  default     = "1h"
}
