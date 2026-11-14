# Acceso mínimo, secretos, Memorystore y VM de soporte.

mock_provider "google" {
  source = "./tests/mocks"
}
mock_provider "random" {}

variables {
  project_id = "proyecto-test"
  image_tag  = "abc123def456"
}

run "secretos_no_van_en_claro" {
  command = plan

  assert {
    condition = alltrue([
      for name in ["POSTGRES_PASSWORD", "JWT_SECRET", "REDIS_PASSWORD", "S3_ACCESS_KEY", "S3_SECRET_KEY"] :
      length([for e in google_cloud_run_v2_service.backend.template[0].containers[0].env : e if e.name == name && try(length(e.value_source), 0) > 0]) == 1
    ])
    error_message = "Cada secreto del backend debe venir de value_source, no de un valor literal"
  }

  assert {
    condition = alltrue([
      for e in google_cloud_run_v2_service.backend.template[0].containers[0].env :
      !contains(["POSTGRES_PASSWORD", "JWT_SECRET", "REDIS_PASSWORD", "S3_ACCESS_KEY", "S3_SECRET_KEY"], e.name) || e.value == null || e.value == ""
    ])
    error_message = "Ningún secreto puede viajar como variable de entorno literal"
  }
}

run "memorystore_privado" {
  command = apply

  assert {
    condition     = google_redis_instance.redis.auth_enabled == true
    error_message = "Memorystore debe requerir AUTH"
  }

  assert {
    condition     = google_redis_instance.redis.connect_mode == "PRIVATE_SERVICE_ACCESS"
    error_message = "Memorystore debe usar Private Service Access"
  }

  assert {
    condition     = google_redis_instance.redis.authorized_network == google_compute_network.main.id
    error_message = "Memorystore debe vivir en la VPC del despliegue"
  }
}

run "vm_de_soporte_sin_ip_publica" {
  command = apply

  assert {
    condition     = length(google_compute_instance.support.network_interface[0].access_config) == 0
    error_message = "La VM de soporte no puede tener IP pública"
  }

  assert {
    condition     = strcontains(google_compute_instance.support.metadata["startup-script"], "clamav/clamav")
    error_message = "La VM de soporte debe arrancar ClamAV"
  }
}

run "firewall_por_rol" {
  command = apply

  assert {
    condition     = toset(google_compute_firewall.clamav.source_tags) == toset(["worker"]) && toset(google_compute_firewall.clamav.target_tags) == toset(["support"])
    error_message = "Solo los workers alcanzan ClamAV"
  }

  assert {
    condition     = toset(google_compute_firewall.smtp.source_tags) == toset(["backend"])
    error_message = "Solo el backend alcanza Mailpit"
  }
}

run "pools_caben_en_cloud_sql" {
  command = plan

  assert {
    condition = (
      var.backend_max_instances * var.backend_db_max_open_conns +
      var.worker_max_instances * var.worker_db_max_open_conns +
      3 <= var.db_max_connections
    )
    error_message = "Los pools de backend y worker deben caber en db_max_connections"
  }
}

run "observabilidad_y_tls" {
  command = plan

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].ip_configuration[0].ssl_mode == "ENCRYPTED_ONLY"
    error_message = "Cloud SQL debe exigir conexiones cifradas"
  }

  assert {
    condition = contains([
      for flag in google_sql_database_instance.postgres.settings[0].database_flags : flag.name
    ], "log_disconnections")
    error_message = "Cloud SQL debe registrar desconexiones"
  }

  assert {
    condition = contains([
      for flag in google_sql_database_instance.postgres.settings[0].database_flags : flag.name
    ], "log_checkpoints")
    error_message = "Cloud SQL debe registrar checkpoints"
  }

  assert {
    condition = contains([
      for flag in google_sql_database_instance.postgres.settings[0].database_flags : flag.name
    ], "log_lock_waits")
    error_message = "Cloud SQL debe registrar esperas de locks"
  }

  assert {
    condition     = google_compute_subnetwork.app.log_config[0].flow_sampling == 0.5
    error_message = "La subred debe tener VPC Flow Logs"
  }

  assert {
    condition     = google_storage_bucket.originals.versioning[0].enabled == true
    error_message = "Los originales deben tener versionado"
  }

  assert {
    condition     = google_storage_bucket.originals.logging[0].log_bucket == google_storage_bucket.logs.name
    error_message = "El bucket de originales debe escribir access logs"
  }

  assert {
    condition     = google_storage_bucket.logs.versioning[0].enabled == true
    error_message = "El bucket de logs debe tener versionado"
  }

  assert {
    condition     = google_compute_instance.support.metadata["block-project-ssh-keys"] == "TRUE"
    error_message = "La VM de soporte debe bloquear claves SSH de proyecto"
  }
}
