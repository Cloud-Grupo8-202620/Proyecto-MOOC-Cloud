resource "google_artifact_registry_repository" "images" {
  repository_id = "${var.name_prefix}-images"
  location      = var.region
  format        = "DOCKER"
  description   = "Imágenes de frontend, backend y workers de la plataforma MOOC"
  labels        = local.labels

  docker_config {
    immutable_tags = true
  }

  depends_on = [google_project_service.enabled]
}

resource "google_artifact_registry_repository_iam_member" "reader" {
  for_each = toset(["frontend", "backend", "worker", "job_admin"])

  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.reader"
  member     = google_service_account.role[each.value].member
}
