# Cloud Function media.scan (entrega 5): disparador, permisos mínimos y
# separación respecto al worker.

mock_provider "google" {
  source = "./tests/mocks"
}
mock_provider "random" {}

variables {
  project_id = "proyecto-test"
  image_tag  = "abc123def456"
}

run "disparada_por_pubsub_con_reintento" {
  command = plan

  assert {
    condition     = google_cloudfunctions2_function.scan.event_trigger[0].event_type == "google.cloud.pubsub.topic.v1.messagePublished"
    error_message = "La función debe dispararse por mensajes de Pub/Sub"
  }

  assert {
    condition     = google_cloudfunctions2_function.scan.event_trigger[0].retry_policy == "RETRY_POLICY_RETRY"
    error_message = "El disparador debe reintentar para no perder escaneos"
  }

  assert {
    condition     = google_cloudfunctions2_function.scan.build_config[0].entry_point == "ScanMedia"
    error_message = "El punto de entrada debe ser ScanMedia"
  }

  assert {
    condition     = google_cloudfunctions2_function.scan.service_config[0].max_instance_count <= 3
    error_message = "La función no puede superar 3 instancias"
  }
}

run "sin_acceso_publico_ni_secretos_en_claro" {
  command = apply

  assert {
    condition     = google_cloudfunctions2_function.scan.service_config[0].ingress_settings == "ALLOW_INTERNAL_ONLY"
    error_message = "La función solo recibe eventos de Eventarc"
  }

  assert {
    condition     = google_cloud_run_v2_service_iam_member.scan_invoker.member == google_service_account.role["scan_event"].member
    error_message = "Solo la cuenta del disparador puede invocar la función"
  }

  assert {
    condition     = length(google_cloudfunctions2_function.scan.service_config[0].secret_environment_variables) == 3
    error_message = "Contraseña de PostgreSQL y claves S3 deben venir de Secret Manager"
  }

  assert {
    condition = alltrue([
      for k in ["POSTGRES_PASSWORD", "S3_ACCESS_KEY", "S3_SECRET_KEY"] :
      !contains(keys(google_cloudfunctions2_function.scan.service_config[0].environment_variables), k)
    ])
    error_message = "Ningún secreto puede viajar como variable de entorno literal"
  }
}

run "worker_ya_no_escanea" {
  command = plan

  assert {
    condition     = !contains(keys(local.worker_env), "CLAMAV_HOST")
    error_message = "El worker no debe conocer ClamAV: el escaneo lo hace la función"
  }

  assert {
    condition     = google_pubsub_topic.scan.name != google_pubsub_topic.jobs.name
    error_message = "El escaneo debe viajar por su propio topic"
  }

  assert {
    condition     = contains(keys(local.backend_env), "PUBSUB_SCAN_TOPIC")
    error_message = "El backend debe publicar el escaneo en el topic de escaneo"
  }

  assert {
    condition     = !contains(keys(google_pubsub_topic_iam_member.publisher), "worker")
    error_message = "El worker ya no publica en Pub/Sub"
  }
}

run "permisos_minimos_de_la_funcion" {
  command = plan

  assert {
    condition     = length([for k, v in local.scan_fn_bucket_roles : k if v.role == "roles/storage.objectAdmin"]) == 1
    error_message = "La función solo administra objetos del bucket de originales"
  }

  assert {
    condition     = toset(local.secret_access["scan_fn"]) == toset([local.secret_postgres_password, local.secret_scan_s3_access, local.secret_scan_s3_secret])
    error_message = "La función solo lee sus tres secretos"
  }
}
