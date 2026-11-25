# Cloud Function (segunda generación) que ejecuta media.scan. Reemplaza la rama
# de escaneo del worker: el backend publica en el topic de escaneo, Eventarc
# entrega cada mensaje a la función, que lee Cloud SQL y Cloud Storage, consulta
# ClamAV por la VPC y encadena el transcode en el topic de media.

locals {
  scan_fn_dir = "${path.module}/../../../backend"

  scan_fn_env = merge(local.postgres_env, local.storage_env, {
    PUBSUB_PROJECT_ID       = var.project_id
    PUBSUB_TOPIC            = google_pubsub_topic.jobs.name
    PUBSUB_SCAN_TOPIC       = google_pubsub_topic.scan.name
    CLAMAV_HOST             = "${google_compute_address.support.address}:3310"
    POSTGRES_MAX_OPEN_CONNS = tostring(var.scan_fn_db_max_open_conns)
    SCAN_MAX_EVENT_AGE      = var.scan_fn_max_event_age
  })

  scan_fn_secrets = {
    POSTGRES_PASSWORD = local.secret_postgres_password
    S3_ACCESS_KEY     = local.secret_scan_s3_access
    S3_SECRET_KEY     = local.secret_scan_s3_secret
  }
}

# Código fuente: Terraform empaqueta backend/ (módulo Go compartido con la API)
# y lo sube a un bucket privado. El nombre del objeto lleva el hash del zip, de
# modo que cualquier cambio de código crea un objeto nuevo y redespliega la
# función con terraform apply, sin pasos manuales.
data "archive_file" "scan_fn" {
  type        = "zip"
  source_dir  = local.scan_fn_dir
  output_path = "${path.module}/.terraform/scan-fn-source.zip"
  excludes = [
    "worker",
    "docs",
    "integration",
    "main",
    "Dockerfile",
    "functions/scanfn/Dockerfile",
    "**/*_test.go",
    "**/*.md",
  ]
}

resource "google_storage_bucket" "function_source" {
  name                        = "${var.name_prefix}-${random_id.bucket_suffix.hex}-fn-src"
  location                    = var.region
  storage_class               = "STANDARD"
  force_destroy               = true
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = local.labels

  logging {
    log_bucket        = google_storage_bucket.logs.name
    log_object_prefix = "fn-src/"
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.enabled]
}

resource "google_storage_bucket_object" "scan_fn" {
  name   = "scan-media/${data.archive_file.scan_fn.output_sha256}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.scan_fn.output_path
}

# Cloud Build compila con una cuenta dedicada y mínima, no con la de Compute.
resource "google_project_iam_member" "scan_build" {
  for_each = toset(["roles/logging.logWriter", "roles/cloudbuild.builds.builder"])

  project = var.project_id
  role    = each.value
  member  = google_service_account.role["scan_build"].member
}

resource "google_storage_bucket_iam_member" "scan_build_source" {
  bucket = google_storage_bucket.function_source.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.role["scan_build"].member
}

resource "google_artifact_registry_repository_iam_member" "scan_build" {
  location   = google_artifact_registry_repository.functions.location
  repository = google_artifact_registry_repository.functions.name
  role       = "roles/artifactregistry.writer"
  member     = google_service_account.role["scan_build"].member
}

resource "google_cloudfunctions2_function" "scan" {
  name        = local.scan_function
  location    = var.region
  description = "media.scan: escaneo antimalware disparado por Pub/Sub (entrega 5)"
  labels      = local.labels

  build_config {
    runtime           = var.scan_fn_runtime
    entry_point       = "ScanMedia"
    service_account   = google_service_account.role["scan_build"].id
    docker_repository = google_artifact_registry_repository.functions.id

    # Paquete de la función dentro del módulo Go de backend/.
    environment_variables = {
      GOOGLE_FUNCTION_SOURCE = "./functions/scanfn"
    }

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.scan_fn.name
      }
    }
  }

  service_config {
    service_account_email            = google_service_account.role["scan_fn"].email
    available_memory                 = var.scan_fn_memory
    available_cpu                    = "1"
    timeout_seconds                  = var.scan_fn_timeout_seconds
    min_instance_count               = var.scan_fn_min_instances
    max_instance_count               = var.scan_fn_max_instances
    max_instance_request_concurrency = 1
    ingress_settings                 = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision   = true
    environment_variables            = local.scan_fn_env

    # Cloud SQL y ClamAV tienen IP privada: Direct VPC Egress, como el worker.
    direct_vpc_egress = "VPC_EGRESS_PRIVATE_RANGES_ONLY"
    direct_vpc_network_interface {
      network    = google_compute_network.main.id
      subnetwork = google_compute_subnetwork.app.id
      tags       = ["scanfn"]
    }

    dynamic "secret_environment_variables" {
      for_each = local.scan_fn_secrets
      content {
        key        = secret_environment_variables.key
        project_id = var.project_id
        secret     = google_secret_manager_secret.app[secret_environment_variables.value].secret_id
        version    = "latest"
      }
    }
  }

  # Eventarc crea la suscripción push hacia la función; RETRY reentrega hasta
  # que la función confirme (o venza la retención del topic).
  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.scan.id
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.role["scan_event"].email
  }

  depends_on = [
    google_project_service.enabled,
    google_secret_manager_secret_version.app,
    google_secret_manager_secret_iam_member.role,
    google_storage_bucket_iam_member.scan_fn,
    google_storage_bucket_iam_member.scan_build_source,
    google_artifact_registry_repository_iam_member.scan_build,
    google_project_iam_member.scan_build,
    google_pubsub_topic_iam_member.publisher,
    google_compute_instance.support,
  ]
}

# Solo el disparador puede invocar la función (sin allUsers).
resource "google_cloud_run_v2_service_iam_member" "scan_invoker" {
  name     = google_cloudfunctions2_function.scan.name
  location = google_cloudfunctions2_function.scan.location
  role     = "roles/run.invoker"
  member   = google_service_account.role["scan_event"].member
}

resource "google_project_iam_member" "scan_event_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = google_service_account.role["scan_event"].member
}
