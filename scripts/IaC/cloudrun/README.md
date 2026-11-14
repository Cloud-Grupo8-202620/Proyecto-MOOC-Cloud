# Terraform — Entrega 4 (Cloud Run + Pub/Sub)

Root autocontenido para desplegar la plataforma MOOC en `proyecto-2-cloud-509714`.
No comparte estado con `scripts/IaC`, que corresponde a la entrega 3 (IaaS). El
prefijo `mooc4` evita colisiones con recursos antiguos.

```
Cloud Run frontend (nginx, 0–3)
        │ proxy /api
Cloud Run backend (Go, 1–3) ──publish──> Pub/Sub topic media-jobs
        │                                      │ push OIDC
        ├── Cloud SQL PostgreSQL               ▼
        ├── Memorystore Redis          Cloud Run worker (0–3)
        ├── Cloud Storage                     ├── Cloud SQL
        └── VM soporte (ClamAV/Mailpit)       ├── Cloud Storage
                                               └── VM soporte (ClamAV)
```

## Requisitos

- Terraform >= 1.14
- Google Cloud CLI autenticado con permisos sobre `proyecto-2-cloud-509714`
- Docker con `buildx` para imágenes `linux/amd64`
- Facturación habilitada

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project proyecto-2-cloud-509714
```

Terraform habilita `run`, `pubsub`, `redis`, `sqladmin`, `servicenetworking`,
`storage`, `secretmanager`, `artifactregistry`, `iam`, `compute`, `logging` y
`monitoring`.

## Despliegue en dos fases

La primera fase solo crea el registro de imágenes; la segunda crea los servicios
que ya referencian las imágenes publicadas.

```bash
cd scripts/IaC/cloudrun
terraform init

# 1. Registro Artifact Registry
terraform apply -target=google_artifact_registry_repository.images

# 2. Imágenes (etiqueta = commit)
./scripts/publish_images.sh
# Imprime IMAGE_TAG=...

# 3. tfvars local (ignorado por git)
cp terraform.tfvars.example terraform.tfvars
# editar project_id e image_tag con lo que imprimió el paso anterior
terraform plan -out=plan.tfplan
terraform apply plan.tfplan
```

Si el apply se interrumpe, volver a ejecutar `terraform plan` y aplicar el plan
nuevo; no reutilizar un plan viejo.

## Después del apply

```bash
terraform output
terraform output -raw frontend_url
terraform output -raw backend_url
terraform output -raw worker_url

# Administrador inicial (lee la contraseña de Secret Manager)
gcloud run jobs execute mooc4-provision-admin --region us-central1 --wait
gcloud secrets versions access latest --secret mooc4-admin-password
```

Mailpit no tiene IP pública. Para verlo:

```bash
gcloud compute ssh mooc4-support --zone us-central1-a --tunnel-through-iap \
  -- -L 8025:127.0.0.1:8025
# http://localhost:8025
```

## Configuración

| Variable | Descripción | Por defecto |
|---|---|---|
| `project_id` | Proyecto de GCP | — |
| `region` / `zone` | Región y zona | `us-central1` / `us-central1-a` |
| `name_prefix` | Prefijo de recursos | `mooc4` |
| `image_tag` | Etiqueta de Artifact Registry | — |
| `frontend_min_instances` / `frontend_max_instances` | Escala del frontend | `0` / `3` |
| `backend_min_instances` / `backend_max_instances` | Escala del backend | `1` / `3` |
| `worker_min_instances` / `worker_max_instances` | Escala del worker | `0` / `3` |
| `frontend_concurrency` / `backend_concurrency` / `worker_concurrency` | Concurrencia | `5` / `10` / `1` |
| `backend_db_max_open_conns` / `worker_db_max_open_conns` | Pool de PostgreSQL por réplica | `4` / `2` |
| `db_tier` | Tier de Cloud SQL | `db-f1-micro` |
| `redis_memory_gb` | Memoria de Memorystore | `1` |
| `pubsub_ack_deadline_seconds` | Ack deadline push | `600` |
| `pubsub_max_delivery_attempts` | Intentos antes de DLQ | `5` |
| `worker_transcode_timeout` | Tope de ffmpeg | `9m` |
| `cors_origins` | Orígenes CORS de buckets | `["*"]` |

## Pub/Sub

- Topic: `mooc4-media-jobs`.
- Suscripción push: `mooc4-media-jobs-push`.
- Endpoint: `https://<worker>/pubsub/push`.
- OIDC: cuenta `mooc4-pubsub-push`, audience = URL del worker.
- Ack deadline 600 s; retry 10–600 s; retención 7 días.
- Dead-letter: `mooc4-media-jobs-dlq`, 5 intentos; suscripción de inspección
  `mooc4-media-jobs-dlq-sub`.

El backend y el worker publican con `roles/pubsub.publisher` sobre el topic.
La cuenta push solo tiene `roles/run.invoker` sobre el worker; el worker no tiene
binding `allUsers`.

## Secretos

- `mooc4-postgres-password`
- `mooc4-jwt-secret`
- `mooc4-redis-password` (AUTH de Memorystore)
- `mooc4-backend-s3-access-key` / `mooc4-backend-s3-secret-key`
- `mooc4-worker-s3-access-key` / `mooc4-worker-s3-secret-key`
- `mooc4-admin-password`

Cada cuenta de servicio solo puede leer los secretos que usa. El estado local de
Terraform contiene valores sensibles; nunca se versiona.

## Pruebas

```bash
terraform fmt -check -recursive
terraform validate
terraform test
```

Los tests usan `mock_provider` y fijan las decisiones: máximo 3 instancias,
un contenedor por servicio, timeouts, concurrencia, VPC, OIDC, DLQ, Memorystore,
ausencia de secretos en claro y presupuesto de conexiones.

## Limitaciones

- Pub/Sub push tiene ack deadline máximo de 600 s; ffmpeg se limita a 540 s.
- Memorystore Basic no tiene HA.
- La VM de soporte es un punto único para ClamAV/Mailpit.
- `db-f1-micro` admite 25 conexiones.
- El frontend proxy comparte su límite de 3 instancias con el tráfico de API.
- `terraform destroy` requiere autorización explícita y elimina Cloud SQL,
  Memorystore, buckets y secretos.
