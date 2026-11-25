resource "google_pubsub_topic" "jobs" {
  name   = local.pubsub_topic
  labels = local.labels

  depends_on = [google_project_service.enabled]
}

resource "google_pubsub_topic" "dlq" {
  name   = local.pubsub_dlq_topic
  labels = local.labels

  depends_on = [google_project_service.enabled]
}

# Topic de escaneo (entrega 5). Eventarc crea y administra la suscripción push
# hacia la Cloud Function; el backend solo publica aquí.
resource "google_pubsub_topic" "scan" {
  name   = local.pubsub_scan_topic
  labels = local.labels

  # Un mensaje de escaneo sin entregar se conserva 7 días: es el techo de los
  # reintentos de Eventarc.
  message_retention_duration = "604800s"

  depends_on = [google_project_service.enabled]
}

# Suscripción push autenticada al worker. El ack deadline de 600 s es el máximo
# de Pub/Sub y está alineado con el timeout de Cloud Run (590 s): la tarea debe
# terminar y persistir antes de que el mensaje se considere no confirmado.
resource "google_pubsub_subscription" "jobs" {
  name                       = local.pubsub_subscription
  topic                      = google_pubsub_topic.jobs.name
  ack_deadline_seconds       = var.pubsub_ack_deadline_seconds
  message_retention_duration = "604800s"
  retain_acked_messages      = false
  enable_message_ordering    = false
  labels                     = local.labels

  expiration_policy {
    ttl = ""
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq.id
    max_delivery_attempts = var.pubsub_max_delivery_attempts
  }

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.worker.uri}/pubsub/push"

    oidc_token {
      service_account_email = google_service_account.role["pubsub_push"].email
      audience              = google_cloud_run_v2_service.worker.uri
    }
  }

  depends_on = [google_project_service.enabled]
}

# Suscripción de inspección del dead-letter topic, para evidencias y soporte.
resource "google_pubsub_subscription" "dlq" {
  name                       = local.pubsub_dlq_sub
  topic                      = google_pubsub_topic.dlq.name
  message_retention_duration = "604800s"
  labels                     = local.labels

  expiration_policy {
    ttl = ""
  }
}

# El backend publica scan y transcode; la función publica el transcode que
# sigue a un escaneo limpio; el worker ya no publica nada.
resource "google_pubsub_topic_iam_member" "publisher" {
  for_each = toset(["backend", "scan_fn"])

  topic  = google_pubsub_topic.jobs.name
  role   = "roles/pubsub.publisher"
  member = google_service_account.role[each.value].member
}

# El agente de Pub/Sub necesita publicar en el DLQ y confirmar en la suscripción.
resource "google_pubsub_topic_iam_member" "dlq_publisher" {
  topic  = google_pubsub_topic.dlq.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription_iam_member" "dlq_subscriber" {
  subscription = google_pubsub_subscription.jobs.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_topic_iam_member" "scan_publisher" {
  topic  = google_pubsub_topic.scan.name
  role   = "roles/pubsub.publisher"
  member = google_service_account.role["backend"].member
}
