locals {
  backend_env = merge(local.postgres_env, local.storage_env, local.pubsub_env, {
    POSTGRES_MAX_OPEN_CONNS = tostring(var.backend_db_max_open_conns)
    REDIS_ADDR              = "${google_redis_instance.redis.host}:${google_redis_instance.redis.port}"
    SMTP_HOST               = google_compute_address.support.address
    SMTP_PORT               = "1025"
    SMTP_USER               = "prueba@test.com"
    API_SHUTDOWN_TIMEOUT    = "25s"
    GIN_MODE                = "release"
  })

  backend_secrets = {
    POSTGRES_PASSWORD = google_secret_manager_secret.app[local.secret_postgres_password].secret_id
    JWT_SECRET        = google_secret_manager_secret.app[local.secret_jwt].secret_id
    REDIS_PASSWORD    = google_secret_manager_secret.app[local.secret_redis_password].secret_id
    S3_ACCESS_KEY     = google_secret_manager_secret.app[local.secret_backend_s3_access].secret_id
    S3_SECRET_KEY     = google_secret_manager_secret.app[local.secret_backend_s3_secret].secret_id
  }

  worker_env = merge(local.postgres_env, local.storage_env, local.pubsub_env, {
    POSTGRES_MAX_OPEN_CONNS  = tostring(var.worker_db_max_open_conns)
    CLAMAV_HOST              = "${google_compute_address.support.address}:3310"
    WORKER_MAX_ATTEMPTS      = tostring(var.pubsub_max_delivery_attempts)
    WORKER_TRANSCODE_TIMEOUT = var.worker_transcode_timeout
    WORKER_SHUTDOWN_TIMEOUT  = "8s"
  })

  worker_secrets = {
    POSTGRES_PASSWORD = google_secret_manager_secret.app[local.secret_postgres_password].secret_id
    S3_ACCESS_KEY     = google_secret_manager_secret.app[local.secret_worker_s3_access].secret_id
    S3_SECRET_KEY     = google_secret_manager_secret.app[local.secret_worker_s3_secret].secret_id
  }

  job_env = merge(local.postgres_env, {
    POSTGRES_MAX_OPEN_CONNS = "2"
    ADMIN_USERNAME          = var.admin_username
    ADMIN_EMAIL             = var.admin_email
  })

  job_secrets = {
    POSTGRES_PASSWORD = google_secret_manager_secret.app[local.secret_postgres_password].secret_id
    ADMIN_PASSWORD    = google_secret_manager_secret.app[local.secret_admin_password].secret_id
  }
}

resource "google_cloud_run_v2_service" "frontend" {
  name                = local.frontend_service
  location            = var.region
  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_ALL"
  labels              = local.labels

  template {
    service_account                  = google_service_account.role["frontend"].email
    execution_environment            = "EXECUTION_ENVIRONMENT_GEN2"
    timeout                          = "300s"
    max_instance_request_concurrency = var.frontend_concurrency

    scaling {
      min_instance_count = var.frontend_min_instances
      max_instance_count = var.frontend_max_instances
    }

    containers {
      name  = "frontend"
      image = local.images.frontend

      ports {
        container_port = 3000
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "BACKEND_URL"
        value = google_cloud_run_v2_service.backend.uri
      }

      startup_probe {
        initial_delay_seconds = 2
        period_seconds        = 10
        timeout_seconds       = 5
        failure_threshold     = 3

        http_get {
          path = "/"
          port = 3000
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.image_tag != ""
      error_message = "Falta image_tag: publica las imágenes y actualiza terraform.tfvars."
    }
  }

  depends_on = [
    google_project_service.enabled,
    google_artifact_registry_repository.images,
  ]
}

resource "google_cloud_run_v2_service" "backend" {
  name                = local.backend_service
  location            = var.region
  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_ALL"
  labels              = local.labels

  template {
    service_account                  = google_service_account.role["backend"].email
    execution_environment            = "EXECUTION_ENVIRONMENT_GEN2"
    timeout                          = "300s"
    max_instance_request_concurrency = var.backend_concurrency

    scaling {
      min_instance_count = var.backend_min_instances
      max_instance_count = var.backend_max_instances
    }

    vpc_access {
      network_interfaces {
        network    = google_compute_network.main.id
        subnetwork = google_compute_subnetwork.app.id
        tags       = ["backend"]
      }
      egress = "PRIVATE_RANGES_ONLY"
    }

    containers {
      name  = "backend"
      image = local.images.backend

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      dynamic "env" {
        for_each = local.backend_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.backend_secrets
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }

      startup_probe {
        initial_delay_seconds = 10
        period_seconds        = 10
        timeout_seconds       = 5
        failure_threshold     = 6

        http_get {
          path = "/health"
          port = 8080
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.image_tag != ""
      error_message = "Falta image_tag: publica las imágenes y actualiza terraform.tfvars."
    }
  }

  depends_on = [
    google_project_service.enabled,
    google_artifact_registry_repository.images,
    google_secret_manager_secret_version.app,
    google_secret_manager_secret_iam_member.role,
    google_compute_instance.support,
  ]
}

resource "google_cloud_run_v2_service" "worker" {
  name                = local.worker_service
  location            = var.region
  deletion_protection = false
  # Pub/Sub llega por Internet, no por la VPC. La protección es IAM: solo la
  # cuenta push tiene run.invoker; no existe binding para allUsers.
  ingress = "INGRESS_TRAFFIC_ALL"
  labels  = local.labels

  template {
    service_account       = google_service_account.role["worker"].email
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"
    # Menor que el ack deadline de Pub/Sub (600 s) para confirmar a tiempo.
    timeout                          = "590s"
    max_instance_request_concurrency = var.worker_concurrency

    scaling {
      min_instance_count = var.worker_min_instances
      max_instance_count = var.worker_max_instances
    }

    vpc_access {
      network_interfaces {
        network    = google_compute_network.main.id
        subnetwork = google_compute_subnetwork.app.id
        tags       = ["worker"]
      }
      egress = "PRIVATE_RANGES_ONLY"
    }

    containers {
      name  = "worker"
      image = local.images.worker

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      dynamic "env" {
        for_each = local.worker_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.worker_secrets
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }

      startup_probe {
        initial_delay_seconds = 10
        period_seconds        = 10
        timeout_seconds       = 5
        failure_threshold     = 6

        http_get {
          path = "/health"
          port = 8080
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.image_tag != ""
      error_message = "Falta image_tag: publica las imágenes y actualiza terraform.tfvars."
    }
  }

  depends_on = [
    google_project_service.enabled,
    google_artifact_registry_repository.images,
    google_secret_manager_secret_version.app,
    google_secret_manager_secret_iam_member.role,
    google_compute_instance.support,
  ]
}

# Frontend y backend son públicos (la API valida JWT en cada ruta protegida).
resource "google_cloud_run_v2_service_iam_member" "frontend_public" {
  name     = google_cloud_run_v2_service.frontend.name
  location = google_cloud_run_v2_service.frontend.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service_iam_member" "backend_public" {
  name     = google_cloud_run_v2_service.backend.name
  location = google_cloud_run_v2_service.backend.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# El worker solo acepta la identidad de la suscripción push.
resource "google_cloud_run_v2_service_iam_member" "worker_push" {
  name     = google_cloud_run_v2_service.worker.name
  location = google_cloud_run_v2_service.worker.location
  role     = "roles/run.invoker"
  member   = google_service_account.role["pubsub_push"].member
}

# Job de una sola ejecución para crear el administrador inicial. Toma la
# contraseña de Secret Manager, nunca de argumentos ni logs.
resource "google_cloud_run_v2_job" "admin" {
  name                = local.admin_job
  location            = var.region
  labels              = local.labels
  deletion_protection = false

  template {
    template {
      service_account = google_service_account.role["job_admin"].email
      timeout         = "600s"
      max_retries     = 0

      vpc_access {
        network_interfaces {
          network    = google_compute_network.main.id
          subnetwork = google_compute_subnetwork.app.id
          tags       = ["job"]
        }
        egress = "PRIVATE_RANGES_ONLY"
      }

      containers {
        name    = "provision-admin"
        image   = local.images.backend
        command = ["./main"]
        args    = ["provision-admin"]

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }

        dynamic "env" {
          for_each = local.job_env
          content {
            name  = env.key
            value = env.value
          }
        }

        dynamic "env" {
          for_each = local.job_secrets
          content {
            name = env.key
            value_source {
              secret_key_ref {
                secret  = env.value
                version = "latest"
              }
            }
          }
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.image_tag != ""
      error_message = "Falta image_tag: publica las imágenes y actualiza terraform.tfvars."
    }
  }

  depends_on = [
    google_project_service.enabled,
    google_artifact_registry_repository.images,
    google_secret_manager_secret_version.app,
    google_secret_manager_secret_iam_member.role,
  ]
}
