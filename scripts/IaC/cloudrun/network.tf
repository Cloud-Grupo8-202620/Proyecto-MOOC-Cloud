locals {
  app_subnet_cidr = "10.10.1.0/24"
  psa_cidr        = "10.86.0.0/16"
}

resource "google_compute_network" "main" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.enabled]
}

resource "google_compute_subnetwork" "app" {
  name                     = "${var.name_prefix}-app-subnet"
  ip_cidr_range            = local.app_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true

  # VPC Flow Logs: muestreo del 50 % cada 10 minutos para diagnosticar tráfico
  # privado entre Cloud Run, Cloud SQL, Memorystore y la VM de soporte.
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# IP fija de la VM de soporte: los servicios Cloud Run la reciben por entorno.
resource "google_compute_address" "support" {
  name         = "${var.name_prefix}-support-ip"
  address_type = "INTERNAL"
  address      = var.support_internal_ip
  region       = var.region
  subnetwork   = google_compute_subnetwork.app.id
}

# Salida a Internet de la VM de soporte para descargar imágenes de Docker Hub.
# Cloud Run con PRIVATE_RANGES_ONLY no usa este NAT para APIs de Google.
resource "google_compute_router" "main" {
  name    = "${var.name_prefix}-router"
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "main" {
  name                               = "${var.name_prefix}-nat"
  router                             = google_compute_router.main.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# SSH solo por IAP para consultar Mailpit o depurar ClamAV.
resource "google_compute_firewall" "iap_ssh" {
  name          = "${var.name_prefix}-allow-iap-ssh"
  network       = google_compute_network.main.name
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["support"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Cloud Function media.scan -> ClamAV. Las etiquetas se aplican a las
# interfaces de Direct VPC Egress, así que el firewall distingue por rol. El
# worker ya no escanea y por eso ya no tiene acceso a clamd.
resource "google_compute_firewall" "clamav" {
  name        = "${var.name_prefix}-allow-clamav"
  network     = google_compute_network.main.name
  direction   = "INGRESS"
  priority    = 1000
  source_tags = ["scanfn"]
  target_tags = ["support"]

  allow {
    protocol = "tcp"
    ports    = ["3310"]
  }
}

# Frontend -> Mailpit UI. La VM no tiene IP pública: el único acceso es el
# proxy HTTPS de Cloud Run en /mailpit/.
resource "google_compute_firewall" "mailpit_ui" {
  name        = "${var.name_prefix}-allow-mailpit-ui"
  network     = google_compute_network.main.name
  direction   = "INGRESS"
  priority    = 1000
  source_tags = ["frontend"]
  target_tags = ["support"]

  allow {
    protocol = "tcp"
    ports    = ["8025"]
  }
}

# Backend -> Mailpit (correo de verificación; en producción se sustituye por SMTP real).
resource "google_compute_firewall" "smtp" {
  name        = "${var.name_prefix}-allow-smtp"
  network     = google_compute_network.main.name
  direction   = "INGRESS"
  priority    = 1000
  source_tags = ["backend"]
  target_tags = ["support"]

  allow {
    protocol = "tcp"
    ports    = ["1025"]
  }
}

# Cloud SQL y Memorystore viven en el rango de Private Service Access; no
# necesitan reglas de firewall de la VPC.
resource "google_compute_global_address" "psa" {
  name          = "${var.name_prefix}-psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]
  deletion_policy         = "REMOVE_PEERING"

  depends_on = [google_project_service.enabled]
}
