resource "random_id" "bucket_suffix" {
  byte_length = 3
}

resource "google_storage_bucket" "originals" {
  name                        = local.bucket_originals
  location                    = var.region
  storage_class               = "STANDARD"
  force_destroy               = true
  uniform_bucket_level_access = true

  cors {
    origin          = var.cors_origins
    method          = ["GET", "HEAD", "PUT", "POST", "PATCH", "DELETE", "OPTIONS"]
    response_header = ["Content-Type", "Authorization", "Upload-Offset", "Upload-Length", "Tus-Resumable", "Location", "Content-Range", "ETag"]
    max_age_seconds = 3600
  }

  # Los sidecars de tusd (.info/.part) expiran; los objetos finales quedan limpios.
  lifecycle_rule {
    condition {
      age            = 7
      matches_prefix = ["tus-meta/"]
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket" "hls" {
  name                        = local.bucket_hls
  location                    = var.region
  storage_class               = "STANDARD"
  force_destroy               = true
  uniform_bucket_level_access = true

  cors {
    origin          = var.cors_origins
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["Content-Type", "Content-Length", "Content-Range", "Accept-Ranges", "ETag"]
    max_age_seconds = 3600
  }
}

resource "google_storage_bucket" "public" {
  name                        = local.bucket_public
  location                    = var.region
  storage_class               = "STANDARD"
  force_destroy               = true
  uniform_bucket_level_access = true

  cors {
    origin          = var.cors_origins
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["Content-Type", "Content-Length", "ETag"]
    max_age_seconds = 3600
  }
}

# Lectura anónima de derivados e imágenes públicas; la API decide qué URL
# revela y las URLs firmadas autorizan las subidas.
resource "google_storage_bucket_iam_member" "hls_public" {
  bucket = google_storage_bucket.hls.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_storage_bucket_iam_member" "public_public" {
  bucket = google_storage_bucket.public.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

locals {
  bucket_access = {
    backend = {
      originals = google_storage_bucket.originals.name
      hls       = google_storage_bucket.hls.name
      public    = google_storage_bucket.public.name
    }
    worker = {
      originals = google_storage_bucket.originals.name
      hls       = google_storage_bucket.hls.name
    }
  }

  bucket_bindings = merge([
    for role, buckets in local.bucket_access : merge([
      for bucket_key, bucket in buckets : {
        for bucket_role in ["roles/storage.objectAdmin", "roles/storage.legacyBucketReader"] :
        "${role}/${bucket_key}/${bucket_role}" => { role = role, bucket = bucket, bucket_role = bucket_role }
      }
    ]...)
  ]...)
}

resource "google_storage_bucket_iam_member" "role" {
  for_each = local.bucket_bindings

  bucket = each.value.bucket
  role   = each.value.bucket_role
  member = google_service_account.role[each.value.role].member
}

# El cliente de almacenamiento comprueba la existencia de los tres buckets al
# arrancar. El worker no escribe en public, pero necesita poder leer sus
# metadatos para no fallar en esa comprobación.
resource "google_storage_bucket_iam_member" "worker_public_reader" {
  bucket = google_storage_bucket.public.name
  role   = "roles/storage.legacyBucketReader"
  member = google_service_account.role["worker"].member
}

# Claves HMAC para la API S3-compatible de Cloud Storage.
resource "google_storage_hmac_key" "role" {
  for_each = toset(["backend", "worker"])

  service_account_email = google_service_account.role[each.value].email
  project               = var.project_id
}
