# Valores de los mocks del proveedor google para terraform test. Los atributos
# calculados que el resto de la configuración consume se fijan con la forma que
# tendrían en GCP.

mock_resource "google_service_account" {
  defaults = {
    name   = "projects/proyecto-test/serviceAccounts/mock-sa@proyecto-test.iam.gserviceaccount.com"
    email  = "mock-sa@proyecto-test.iam.gserviceaccount.com"
    member = "serviceAccount:mock-sa@proyecto-test.iam.gserviceaccount.com"
  }
}

mock_resource "google_compute_network" {
  defaults = {
    id = "projects/proyecto-test/global/networks/mooc4-vpc"
  }
}

mock_resource "google_compute_subnetwork" {
  defaults = {
    id = "projects/proyecto-test/regions/us-central1/subnetworks/mooc4-app-subnet"
  }
}

mock_resource "google_compute_address" {
  defaults = {
    address = "10.10.1.30"
  }
}

mock_resource "google_compute_instance" {
  defaults = {
    id = "projects/proyecto-test/zones/us-central1-a/instances/mooc4-support"
  }
}

mock_data "google_compute_image" {
  defaults = {
    self_link = "https://www.googleapis.com/compute/v1/projects/cos-cloud/global/images/cos-stable-mock"
  }
}

mock_data "google_project" {
  defaults = {
    number = "123456789"
  }
}

mock_resource "google_sql_database_instance" {
  defaults = {
    private_ip_address = "10.86.0.3"
    connection_name    = "proyecto-test:us-central1:mooc4-postgres"
  }
}

mock_resource "google_redis_instance" {
  defaults = {
    host        = "10.86.0.4"
    port        = 6379
    auth_string = "redis-mock-password"
  }
}

mock_resource "google_storage_hmac_key" {
  defaults = {
    access_id = "GOOGMOCKACCESSID"
    secret    = "mock-hmac-secret"
  }
}

mock_resource "google_cloud_run_v2_service" {
  defaults = {
    uri = "https://mock-service-uc.a.run.app"
  }
}

mock_resource "google_pubsub_topic" {
  defaults = {
    id = "projects/proyecto-test/topics/mooc4-media-jobs-dlq"
  }
}

mock_resource "google_storage_bucket" {
  defaults = {
    name = "mooc4-mock-bucket"
  }
}
