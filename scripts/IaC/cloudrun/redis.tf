# Redis administrado para sesiones revocables, códigos de verificación y locks
# de TUS. No es el mecanismo de mensajería: la cola es Pub/Sub.
resource "google_redis_instance" "redis" {
  name               = "${var.name_prefix}-redis"
  display_name       = "Sesiones y locks de la plataforma MOOC"
  tier               = "BASIC"
  memory_size_gb     = var.redis_memory_gb
  region             = var.region
  location_id        = var.zone
  redis_version      = var.redis_version
  auth_enabled       = true
  authorized_network = google_compute_network.main.id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"

  deletion_protection = false
  labels              = local.labels

  depends_on = [google_service_networking_connection.psa]
}
