locals {
  labels = {
    project     = var.name_prefix
    environment = "entrega4"
    managed_by  = "terraform"
  }

  # Nombres de los tres servicios Cloud Run y del Job administrativo.
  frontend_service = "${var.name_prefix}-frontend"
  backend_service  = "${var.name_prefix}-backend"
  worker_service   = "${var.name_prefix}-worker"
  admin_job        = "${var.name_prefix}-provision-admin"

  # Artefactos.
  registry_host = "${var.region}-docker.pkg.dev"
  image_repo    = "${local.registry_host}/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
  images = {
    frontend = "${local.image_repo}/frontend:${var.image_tag}"
    backend  = "${local.image_repo}/backend:${var.image_tag}"
    worker   = "${local.image_repo}/worker:${var.image_tag}"
  }

  # Buckets con sufijo aleatorio: los nombres de Cloud Storage son globales.
  bucket_originals = "${var.name_prefix}-${random_id.bucket_suffix.hex}-originals"
  bucket_hls       = "${var.name_prefix}-${random_id.bucket_suffix.hex}-hls"
  bucket_public    = "${var.name_prefix}-${random_id.bucket_suffix.hex}-public"
  bucket_logs      = "${var.name_prefix}-${random_id.bucket_suffix.hex}-logs"

  # Nombres de Pub/Sub.
  pubsub_topic        = "${var.name_prefix}-media-jobs"
  pubsub_subscription = "${var.name_prefix}-media-jobs-push"
  pubsub_dlq_topic    = "${var.name_prefix}-media-jobs-dlq"
  pubsub_dlq_sub      = "${var.name_prefix}-media-jobs-dlq-sub"

  # Secret Manager. Ningún valor viaja en la imagen ni en el tfvars.
  secret_postgres_password = "${var.name_prefix}-postgres-password"
  secret_jwt               = "${var.name_prefix}-jwt-secret"
  secret_redis_password    = "${var.name_prefix}-redis-password"
  secret_backend_s3_access = "${var.name_prefix}-backend-s3-access-key"
  secret_backend_s3_secret = "${var.name_prefix}-backend-s3-secret-key"
  secret_worker_s3_access  = "${var.name_prefix}-worker-s3-access-key"
  secret_worker_s3_secret  = "${var.name_prefix}-worker-s3-secret-key"
  secret_admin_password    = "${var.name_prefix}-admin-password"
  secret_mailpit_auth      = "${var.name_prefix}-mailpit-auth"

  # Entorno común de los servicios que hablan con PostgreSQL y Cloud Storage.
  postgres_env = {
    POSTGRES_HOST    = google_sql_database_instance.postgres.private_ip_address
    POSTGRES_PORT    = "5432"
    POSTGRES_USER    = google_sql_user.app.name
    POSTGRES_DB      = google_sql_database.app.name
    POSTGRES_SSLMODE = "require"
  }

  storage_env = {
    S3_ENDPOINT         = "storage.googleapis.com"
    S3_PUBLIC_ENDPOINT  = "https://storage.googleapis.com"
    S3_USE_SSL          = "true"
    S3_REGION           = "auto"
    S3_BUCKET_ORIGINALS = google_storage_bucket.originals.name
    S3_BUCKET_HLS       = google_storage_bucket.hls.name
    S3_BUCKET_PUBLIC    = google_storage_bucket.public.name
    CDN_BASE_URL        = ""
  }

  pubsub_env = {
    PUBSUB_PROJECT_ID = var.project_id
    PUBSUB_TOPIC      = google_pubsub_topic.jobs.name
  }
}
