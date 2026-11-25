terraform {
  required_version = ">= 1.14"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # El estado contiene secretos generados (contraseñas, claves HMAC): nunca se
  # versiona (*.tfstate está en .gitignore). Por defecto es local; para un
  # estado remoto y cifrado en un bucket que NO gestiona este despliegue, copia
  # backend.gcs.tfbackend.example a backend.gcs.tfbackend, descomenta el bloque
  # siguiente y ejecuta: terraform init -backend-config=backend.gcs.tfbackend
  #
  # backend "gcs" {}
}
