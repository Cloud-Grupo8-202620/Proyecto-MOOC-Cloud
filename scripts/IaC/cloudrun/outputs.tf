output "project_id" {
  description = "Proyecto donde se desplegó la entrega 4"
  value       = var.project_id
}

output "region" {
  description = "Región de los servicios"
  value       = var.region
}

output "frontend_url" {
  description = "URL pública del frontend"
  value       = google_cloud_run_v2_service.frontend.uri
}

output "backend_url" {
  description = "URL pública del backend (también se alcanza por el proxy del frontend)"
  value       = google_cloud_run_v2_service.backend.uri
}

output "worker_url" {
  description = "URL privada por IAM del worker; solo la usa la suscripción push"
  value       = google_cloud_run_v2_service.worker.uri
}

output "image_repository" {
  description = "Repositorio de Artifact Registry donde publica scripts/publish_images.sh"
  value       = local.image_repo
}

output "image_tag" {
  description = "Etiqueta de imagen desplegada"
  value       = var.image_tag
}

output "pubsub_topic" {
  description = "Topic de tareas asíncronas"
  value       = google_pubsub_topic.jobs.name
}

output "pubsub_subscription" {
  description = "Suscripción push autenticada al worker"
  value       = google_pubsub_subscription.jobs.name
}

output "pubsub_dlq_topic" {
  description = "Topic de mensajes que agotaron los reintentos"
  value       = google_pubsub_topic.dlq.name
}

output "postgres_private_ip" {
  description = "IP privada de Cloud SQL"
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "redis_host" {
  description = "Host privado de Memorystore"
  value       = google_redis_instance.redis.host
}

output "support_internal_ip" {
  description = "IP privada de la VM de ClamAV y Mailpit"
  value       = google_compute_address.support.address
}

output "service_accounts" {
  description = "Cuenta de servicio de cada rol"
  value       = { for role, sa in google_service_account.role : role => sa.email }
}

output "admin_username" {
  description = "Usuario administrador inicial"
  value       = var.admin_username
}

output "admin_email" {
  description = "Correo del administrador inicial"
  value       = var.admin_email
}

output "admin_password_secret" {
  description = "Nombre del secreto con la contraseña inicial; se lee con gcloud secrets versions access"
  value       = google_secret_manager_secret.app[local.secret_admin_password].secret_id
}

output "pubsub_scan_topic" {
  description = "Topic de escaneo que activa la Cloud Function"
  value       = google_pubsub_topic.scan.name
}

output "scan_function" {
  description = "Cloud Function media.scan"
  value = {
    name     = google_cloudfunctions2_function.scan.name
    location = google_cloudfunctions2_function.scan.location
    trigger  = google_cloudfunctions2_function.scan.event_trigger[0].trigger
    service  = google_cloudfunctions2_function.scan.service_config[0].service
  }
}

output "scan_function_source" {
  description = "Objeto de Cloud Storage con el código desplegado (hash SHA-256 del zip)"
  value       = "gs://${google_storage_bucket_object.scan_fn.bucket}/${google_storage_bucket_object.scan_fn.name}"
}
