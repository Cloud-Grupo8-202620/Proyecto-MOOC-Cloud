locals {
  required_apis = toset([
    "compute.googleapis.com",
    "run.googleapis.com",
    "pubsub.googleapis.com",
    "redis.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "storage.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
  ])

  service_accounts = {
    frontend    = "Frontend Cloud Run"
    backend     = "Backend Cloud Run"
    worker      = "Workers Cloud Run"
    pubsub_push = "Suscripción push de Pub/Sub"
    job_admin   = "Job de provisión de administrador"
    support     = "VM de soporte (ClamAV y Mailpit)"
    scan_fn     = "Cloud Function media.scan (ejecución)"
    scan_build  = "Cloud Function media.scan (build de Cloud Build)"
    scan_event  = "Disparador Eventarc de la Cloud Function media.scan"
  }
}

resource "google_project_service" "enabled" {
  for_each = local.required_apis

  service            = each.value
  disable_on_destroy = false
}

data "google_project" "this" {
  project_id = var.project_id
}

resource "google_service_account" "role" {
  for_each = local.service_accounts

  account_id   = "${var.name_prefix}-${replace(each.key, "_", "-")}"
  display_name = each.value

  depends_on = [google_project_service.enabled]
}

# La cuenta push solo puede invocar el worker. Pub/Sub firma el OIDC con esta
# identidad y Cloud Run valida el token antes de entregar la solicitud.
resource "google_service_account_iam_member" "pubsub_token_creator" {
  service_account_id = google_service_account.role["pubsub_push"].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# Eventarc entrega el mensaje a la función firmando un OIDC con la cuenta del
# disparador; el agente de Pub/Sub necesita poder emitir ese token.
resource "google_service_account_iam_member" "scan_event_token_creator" {
  service_account_id = google_service_account.role["scan_event"].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# ---------------------------------------------------------------------------
# Secretos generados por el despliegue
# ---------------------------------------------------------------------------

resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "random_password" "jwt" {
  length  = 48
  special = true
}

resource "random_password" "admin" {
  length  = 32
  special = false
}

resource "random_password" "mailpit" {
  length  = 24
  special = false
}

locals {
  secret_values = {
    (local.secret_postgres_password) = random_password.postgres.result
    (local.secret_jwt)               = random_password.jwt.result
    (local.secret_redis_password)    = google_redis_instance.redis.auth_string
    (local.secret_backend_s3_access) = google_storage_hmac_key.role["backend"].access_id
    (local.secret_backend_s3_secret) = google_storage_hmac_key.role["backend"].secret
    (local.secret_worker_s3_access)  = google_storage_hmac_key.role["worker"].access_id
    (local.secret_worker_s3_secret)  = google_storage_hmac_key.role["worker"].secret
    (local.secret_scan_s3_access)    = google_storage_hmac_key.role["scan_fn"].access_id
    (local.secret_scan_s3_secret)    = google_storage_hmac_key.role["scan_fn"].secret
    (local.secret_admin_password)    = random_password.admin.result
    (local.secret_mailpit_auth)      = random_password.mailpit.result
  }

  # Qué secretos puede leer cada identidad: exactamente los que usa.
  secret_access = {
    backend = [
      local.secret_postgres_password,
      local.secret_jwt,
      local.secret_redis_password,
      local.secret_backend_s3_access,
      local.secret_backend_s3_secret,
    ]
    worker = [
      local.secret_postgres_password,
      local.secret_worker_s3_access,
      local.secret_worker_s3_secret,
    ]
    scan_fn = [
      local.secret_postgres_password,
      local.secret_scan_s3_access,
      local.secret_scan_s3_secret,
    ]
    job_admin = [
      local.secret_postgres_password,
      local.secret_admin_password,
    ]
    support = [
      local.secret_mailpit_auth,
    ]
  }

  secret_bindings = merge([
    for role, secrets in local.secret_access : {
      for secret in secrets : "${role}/${secret}" => { role = role, secret = secret }
    }
  ]...)
}

resource "google_secret_manager_secret" "app" {
  for_each = toset(keys(local.secret_values))

  secret_id = each.value

  replication {
    auto {}
  }

  depends_on = [google_project_service.enabled]
}

resource "google_secret_manager_secret_version" "app" {
  for_each = toset(keys(local.secret_values))

  secret      = google_secret_manager_secret.app[each.value].id
  secret_data = local.secret_values[each.value]
}

resource "google_secret_manager_secret_iam_member" "role" {
  for_each = local.secret_bindings

  project   = var.project_id
  secret_id = google_secret_manager_secret.app[each.value.secret].id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.role[each.value.role].member
}
