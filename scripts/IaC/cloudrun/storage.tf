resource "random_id" "bucket_suffix" {
  byte_length = 3
}

# Bucket privado para los access logs de los otros tres buckets. No se le
# habilita logging para evitar recursión; # NOSONAR documenta la excepción.
resource "google_storage_bucket" "logs" { # NOSONAR: bucket de logs sin auto-logging.
  name                        = local.bucket_logs
  location                    = var.region
  storage_class               = "STANDARD"
  force_destroy               = true
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 7
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket" "originals" {
  name                        = local.bucket_originals
  location                    = var.region
  storage_class               = "STANDARD"
  force_destroy               = true
  uniform_bucket_level_access = true

  logging {
    log_bucket        = google_storage_bucket.logs.name
    log_object_prefix = "originals/"
  }

  versioning {
    enabled = true
  }

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

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 7
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

  logging {
    log_bucket        = google_storage_bucket.logs.name
    log_object_prefix = "hls/"
  }

  versioning {
    enabled = true
  }

  cors {
    origin          = var.cors_origins
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["Content-Type", "Content-Length", "Content-Range", "Accept-Ranges", "ETag"]
    max_age_seconds = 3600
  }
  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 7
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket" "public" {
  name                        = local.bucket_public
  location                    = var.region
  storage_class               = "STANDARD"
  force_destroy               = true
  uniform_bucket_level_access = true

  logging {
    log_bucket        = google_storage_bucket.logs.name
    log_object_prefix = "public/"
  }

  versioning {
    enabled = true
  }

  cors {
    origin          = var.cors_origins
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["Content-Type", "Content-Length", "ETag"]
    max_age_seconds = 3600
  }
  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 7
    }
    action {
      type = "Delete"
    }
  }
}

# Lectura anónima de derivados e imágenes públicas; la API decide qué URL
# revela y las URLs firmadas autorizan las subidas.
resource "google_storage_bucket_iam_member" "hls_public" {
  bucket = google_storage_bucket.hls.name
  role   = "roles/storage.objectViewer"
  member = "allUsers" # NOSONAR: HLS público por diseño; la API decide qué URL revelar.
}

resource "google_storage_bucket_iam_member" "public_public" {
  bucket = google_storage_bucket.public.name
  role   = "roles/storage.objectViewer"
  member = "allUsers" # NOSONAR: imágenes y badges públicos por diseño.
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

  # La función solo lee y elimina originales (cuarentena). El cliente de
  # almacenamiento comprueba que existan los tres buckets al arrancar, por eso
  # recibe además lectura de metadatos en hls y public (como el worker).
  scan_fn_bucket_roles = {
    "originals/objectAdmin"        = { bucket = google_storage_bucket.originals.name, role = "roles/storage.objectAdmin" }
    "originals/legacyBucketReader" = { bucket = google_storage_bucket.originals.name, role = "roles/storage.legacyBucketReader" }
    "hls/legacyBucketReader"       = { bucket = google_storage_bucket.hls.name, role = "roles/storage.legacyBucketReader" }
    "public/legacyBucketReader"    = { bucket = google_storage_bucket.public.name, role = "roles/storage.legacyBucketReader" }
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

resource "google_storage_bucket_iam_member" "scan_fn" {
  for_each = local.scan_fn_bucket_roles

  bucket = each.value.bucket
  role   = each.value.role
  member = google_service_account.role["scan_fn"].member
}

# Claves HMAC para la API S3-compatible de Cloud Storage.
resource "google_storage_hmac_key" "role" {
  for_each = toset(["backend", "worker", "scan_fn"])

  service_account_email = google_service_account.role[each.value].email
  project               = var.project_id
}
