# Entrega 5 — Despliegue con Terraform

Todo el despliegue (Cloud Run, Pub/Sub, Cloud Function, cuentas de servicio, permisos, secretos, red, Cloud SQL, buckets) lo gestiona el root `scripts/IaC/cloudrun` con `terraform init`, `plan` y `apply`. No hay recursos del alcance configurados a mano.

## 1. Prerrequisitos

- Terraform ≥ 1.14, Google Cloud CLI autenticado (`gcloud auth application-default login`) y Docker con `buildx`.
- Proyecto con facturación y un usuario con permisos para crear Cloud Run, Cloud Functions, Eventarc, Pub/Sub, Cloud SQL, Memorystore, Storage, Secret Manager, Artifact Registry, IAM y redes (en un proyecto de curso, `Owner`). Terraform habilita las APIs que necesita (`google_project_service`), incluidas `cloudfunctions`, `cloudbuild` y `eventarc`.
- Go no es necesario: Cloud Build compila la función en Google Cloud. Solo hace falta si se quieren ejecutar las pruebas (`cd backend && go test ./...`).

## 2. Parametrización

Copiar `terraform.tfvars.example` a `terraform.tfvars` (ignorado por git). Variables principales:

| Variable | Defecto | Uso |
|---|---|---|
| `project_id` | — (obligatoria) | Proyecto de despliegue |
| `region` / `zone` | `us-central1` / `us-central1-a` | Ubicación de todos los recursos |
| `name_prefix` | `mooc4` | Prefijo de todos los recursos; cámbialo para convivir con otro despliegue |
| `image_tag` | — (obligatoria) | Etiqueta de `publish_images.sh` |
| `*_min_instances`, `*_max_instances` | 0 / 3 | Escalamiento de frontend, backend y worker |
| `scan_fn_runtime` | `go126` | Runtime de la función; debe cubrir la versión de `backend/go.mod` |
| `scan_fn_memory`, `scan_fn_timeout_seconds` | `1Gi`, 540 | Recursos de la función |
| `scan_fn_min_instances`, `scan_fn_max_instances` | 0 / 3 | Escalamiento de la función |
| `scan_fn_max_event_age` | `1h` | Ventana de reintentos antes de marcar `failed` |

Los secretos (contraseña de PostgreSQL, JWT, Redis, admin, Mailpit, claves HMAC) los genera Terraform con `random_password`/`google_storage_hmac_key` y viajan a Secret Manager; ningún valor está en el repositorio ni en `terraform.tfvars`.

### Estado de Terraform

`*.tfstate`, `*.tfvars`, `*.tfplan`, `*.tfbackend` y `.terraform/` están en `.gitignore`. El estado contiene los secretos generados, por eso para un uso compartido debe ir a un bucket **fuera** del despliegue:

```bash
gcloud storage buckets create gs://<PROYECTO>-tfstate --location us-central1 --uniform-bucket-level-access
gcloud storage buckets update gs://<PROYECTO>-tfstate --versioning
cp scripts/IaC/cloudrun/backend.gcs.tfbackend.example scripts/IaC/cloudrun/backend.gcs.tfbackend   # editar bucket
# descomentar  backend "gcs" {}  en terraform.tf
terraform init -backend-config=backend.gcs.tfbackend
```

## 3. Preparación de imágenes y código

- **Imágenes** (frontend, backend, worker): `publish_images.sh` las construye y publica en Artifact Registry; la etiqueta va en `image_tag`.
- **Código de la función**: no hay paso manual. Terraform empaqueta `backend/` (excluye `worker/`, pruebas y documentación), lo sube a `…-fn-src` con el hash del zip en el nombre y Cloud Build lo compila. Cambiar el código cambia el hash y `terraform apply` redespliega la función.

## 4. Pasos

```bash
cd scripts/IaC/cloudrun
cp terraform.tfvars.example terraform.tfvars        # project_id; image_tag después
terraform init
terraform apply -target=google_artifact_registry_repository.images   # registro vacío para publicar
./scripts/publish_images.sh                          # imprime IMAGE_TAG=...
# poner image_tag en terraform.tfvars
terraform plan -out=plan.tfplan
terraform apply plan.tfplan
gcloud run jobs execute mooc4-provision-admin --region us-central1 --wait   # admin inicial
```

El primer `apply` tarda ~15–20 min (Cloud SQL, Memorystore, build de la función). Actualizaciones posteriores: cambiar código o variables y repetir `terraform plan` / `terraform apply`; `plan` solo debe mostrar los recursos afectados (p. ej. un objeto de código nuevo + la función).

## 5. Recursos existentes

- **Convivir con otro despliegue** (p. ej. la entrega 4 en el mismo proyecto): usar otro `name_prefix` en `terraform.tfvars`; los buckets además llevan sufijo aleatorio.
- **Adoptar recursos ya creados** (p. ej. el despliegue de la entrega 4): `terraform import` por recurso, por ejemplo `terraform import google_pubsub_topic.jobs projects/<PROYECTO>/topics/mooc4-media-jobs`, y revisar con `terraform plan` hasta que no haya cambios inesperados. Si el estado de la entrega 4 se conserva (mismo directorio/backend), `apply` solo añade lo nuevo (función, topic de escaneo, cuentas, firewall) y modifica backend y worker.
- **APIs ya habilitadas**: `google_project_service` es idempotente y usa `disable_on_destroy = false`.
- **Eliminar**: `terraform destroy` borra Cloud SQL, Redis, buckets y secretos; solo con autorización explícita.

## 6. Verificación

```bash
terraform output scan_function
gcloud functions describe mooc4-scan-media --gen2 --region us-central1 \
  --format='yaml(state,serviceConfig.environmentVariables,eventTrigger)'
# tarea real: subir un video desde la UI/API o publicar a mano
RESOURCE_ID=<id> OBJECT_KEY=<clave> REPUBLISH=1 scripts/entrega5/probar_scan.sh
```

Pruebas sin cuenta de GCP: `terraform fmt -check -recursive && terraform validate && terraform test` y `cd backend && go test ./...` (las de `scanner` usan `POSTGRES_TEST_DSN`).

## 7. Limitaciones y riesgos conocidos

- El runtime `go126` y la variable de build `GOOGLE_FUNCTION_SOURCE=./functions/scanfn` deben ser aceptados por Cloud Build en el proyecto; si el runtime aún no existe, ajustar `scan_fn_runtime` (la versión de `go.mod` debe ser compatible).
- Eventarc administra la suscripción de la función: sin DLQ por intentos (se usa la ventana `scan_fn_max_event_age`).
- Con `scan_fn_max_instances = 3` y concurrencia 1 la función usa como máximo 3 conexiones a Cloud SQL (el presupuesto de 25 está validado en `variables.tf`).
- La VM de soporte (ClamAV) sigue siendo un punto único de falla.
