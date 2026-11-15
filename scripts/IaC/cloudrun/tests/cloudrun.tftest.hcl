# Decisiones de la entrega 4 sin tocar GCP: tres servicios Cloud Run, máximo 3
# instancias, un contenedor por instancia y límites alineados con Pub/Sub.

mock_provider "google" {
  source = "./tests/mocks"
}
mock_provider "random" {}

variables {
  project_id = "proyecto-test"
  image_tag  = "abc123def456"
}

run "tres_servicios_con_maximo_tres" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_service.frontend.template[0].scaling[0].max_instance_count == 3
    error_message = "El frontend debe tener máximo 3 instancias"
  }

  assert {
    condition     = google_cloud_run_v2_service.backend.template[0].scaling[0].max_instance_count == 3
    error_message = "El backend debe tener máximo 3 instancias"
  }

  assert {
    condition     = google_cloud_run_v2_service.worker.template[0].scaling[0].max_instance_count == 3
    error_message = "El worker debe tener máximo 3 instancias"
  }

  assert {
    condition = (
      google_cloud_run_v2_service.frontend.scaling[0].max_instance_count == 3 &&
      google_cloud_run_v2_service.backend.scaling[0].max_instance_count == 3 &&
      google_cloud_run_v2_service.worker.scaling[0].max_instance_count == 3
    )
    error_message = "El escalamiento a nivel de servicio debe tener máximo 3"
  }

  assert {
    condition = (
      google_cloud_run_v2_service.frontend.scaling[0].min_instance_count == 0 &&
      google_cloud_run_v2_service.backend.scaling[0].min_instance_count == 0 &&
      google_cloud_run_v2_service.worker.scaling[0].min_instance_count == 0
    )
    error_message = "Los tres servicios deben poder escalar desde 0"
  }

  assert {
    condition = (
      google_cloud_run_v2_service.frontend.template[0].scaling[0].min_instance_count == 0 &&
      google_cloud_run_v2_service.backend.template[0].scaling[0].min_instance_count == 0 &&
      google_cloud_run_v2_service.worker.template[0].scaling[0].min_instance_count == 0
    )
    error_message = "Los mínimos documentados son 0, 0 y 0"
  }
}

run "un_contenedor_por_instancia" {
  command = plan

  assert {
    condition = (
      length(google_cloud_run_v2_service.frontend.template[0].containers) == 1 &&
      length(google_cloud_run_v2_service.backend.template[0].containers) == 1 &&
      length(google_cloud_run_v2_service.worker.template[0].containers) == 1
    )
    error_message = "Cada servicio debe tener exactamente un contenedor de aplicación"
  }
}

run "limites_de_ejecucion" {
  command = plan

  assert {
    condition = (
      google_cloud_run_v2_service.frontend.template[0].timeout == "300s" &&
      google_cloud_run_v2_service.backend.template[0].timeout == "300s" &&
      google_cloud_run_v2_service.worker.template[0].timeout == "590s"
    )
    error_message = "Los timeouts deben ser 300 s, 300 s y 590 s"
  }

  assert {
    condition = (
      google_cloud_run_v2_service.frontend.template[0].max_instance_request_concurrency == 5 &&
      google_cloud_run_v2_service.backend.template[0].max_instance_request_concurrency == 10 &&
      google_cloud_run_v2_service.worker.template[0].max_instance_request_concurrency == 1
    )
    error_message = "La concurrencia documentada no coincide"
  }

  assert {
    condition = (
      google_cloud_run_v2_service.worker.template[0].containers[0].resources[0].limits["cpu"] == "2" &&
      google_cloud_run_v2_service.worker.template[0].containers[0].resources[0].limits["memory"] == "2Gi"
    )
    error_message = "El worker debe tener 2 vCPU y 2 GiB para ffmpeg y ClamAV"
  }
}

run "backend_y_worker_usan_vpc_directa" {
  command = plan

  assert {
    condition = (
      length(google_cloud_run_v2_service.backend.template[0].vpc_access[0].network_interfaces) == 1 &&
      length(google_cloud_run_v2_service.worker.template[0].vpc_access[0].network_interfaces) == 1
    )
    error_message = "Backend y worker necesitan Direct VPC Egress para Cloud SQL, Redis y ClamAV"
  }

  assert {
    condition = (
      google_cloud_run_v2_service.backend.template[0].vpc_access[0].network_interfaces[0].tags[0] == "backend" &&
      google_cloud_run_v2_service.worker.template[0].vpc_access[0].network_interfaces[0].tags[0] == "worker"
    )
    error_message = "Las etiquetas de red deben distinguir backend y worker"
  }
}
