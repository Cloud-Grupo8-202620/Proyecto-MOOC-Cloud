data "google_compute_image" "cos" {
  project = "cos-cloud"
  family  = "cos-stable"
}

# ClamAV y Mailpit no se pueden ejecutar como servicios Cloud Run: ClamAV habla
# TCP y Mailpit es el SMTP de pruebas. Se mantienen en una VM pequeña sin IP
# pública; las réplicas de Cloud Run no guardan estado en ella.
resource "google_compute_instance" "support" {
  name                      = "${var.name_prefix}-support"
  machine_type              = var.support_machine_type
  zone                      = var.zone
  tags                      = ["support"]
  labels                    = merge(local.labels, { role = "support" })
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = data.google_compute_image.cos.self_link
      size  = 30
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.app.id
    network_ip = google_compute_address.support.address
    # Sin access_config: no tiene IP pública.
  }

  service_account {
    email  = google_service_account.role["support"].email
    scopes = ["cloud-platform"]
  }

  metadata = {
    "startup-script" = file("${path.module}/scripts/support_startup.sh")
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  depends_on = [google_project_service.enabled, google_compute_router_nat.main]
}
