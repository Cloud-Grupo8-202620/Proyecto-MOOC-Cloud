terraform {
  required_version = ">= 1.14"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # Estado local por defecto. No se comparte con el root de entrega 3: este
  # despliegue tiene su propio ciclo de vida y su propio prefijo de recursos.
  #
  # backend "gcs" {
  #   bucket = "<PROJECT_ID>-tfstate"
  #   prefix = "entrega4-cloudrun"
  # }
}
