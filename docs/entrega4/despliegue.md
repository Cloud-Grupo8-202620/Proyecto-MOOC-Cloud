# Guía de despliegue — Entrega 4

Proyecto: `proyecto-2-cloud-509714`.
Región: `us-central1`.
Prefijo de recursos: `mooc4`.

Estado: **desplegado y verificado el 2026-11-14** en `proyecto-2-cloud-509714`
con la imagen `ed67d93c2666`; **retirado** con `terraform destroy` el mismo día.
Apply de 103 recursos, Job de administrador ejecutado y recorrido Playwright
completo contra Cloud Run aprobado. Evidencias en
[RESUMEN-2026-11-14.md](evidencia/RESUMEN-2026-11-14.md) y
[RETIRO-2026-11-14.md](evidencia/RETIRO-2026-11-14.md).

## 1. Requisitos

- Terraform >= 1.14 y Google Cloud CLI autenticado.
- Docker con `buildx` para publicar `linux/amd64`.
- Facturación habilitada y permisos para crear Cloud Run, Pub/Sub, Cloud SQL,
  Memorystore, Storage, Secret Manager, Artifact Registry, IAM y redes.
- `gcloud config set project proyecto-2-cloud-509714`.

## 2. Publicar imágenes y aplicar

```bash
cd scripts/IaC/cloudrun
terraform init
terraform apply -target=google_artifact_registry_repository.images
./scripts/publish_images.sh
cp terraform.tfvars.example terraform.tfvars
# editar project_id e image_tag
terraform plan -out=plan.tfplan
terraform apply plan.tfplan
```

La primera fase crea `us-central1-docker.pkg.dev/proyecto-2-cloud-509714/mooc4-images`.
La segunda crea los tres servicios Cloud Run, el Job administrativo, Pub/Sub,
Cloud SQL, Memorystore, los buckets, la VM de soporte y los secretos.

## 3. Verificar servicios y límites

```bash
terraform output
gcloud run services list --region us-central1 \
  --format='table(metadata.name,status.url)'

for s in mooc4-frontend mooc4-backend mooc4-worker; do
  echo "== $s"
  gcloud run services describe "$s" --region us-central1 \
    --format='yaml(spec.template.spec.scaling,spec.template.spec.containers[0].resources,spec.template.spec.timeoutSeconds,spec.template.spec.containerConcurrency,status.url)'
done
```

Valores esperados:

| Servicio | Mín. | Máx. | CPU | Memoria | Concurrencia | Timeout |
|---|---:|---:|---:|---:|---:|---:|
| `mooc4-frontend` | 0 | 3 | 1 | 512Mi | 5 | 300 s |
| `mooc4-backend` | 1 | 3 | 1 | 512Mi | 10 | 300 s |
| `mooc4-worker` | 0 | 3 | 2 | 2Gi | 1 | 590 s |

## 4. Crear el administrador inicial

```bash
gcloud run jobs execute mooc4-provision-admin --region us-central1 --wait
gcloud secrets versions access latest --secret mooc4-admin-password
```

El Job usa la imagen del backend, `./main provision-admin`, y lee
`ADMIN_USERNAME`, `ADMIN_EMAIL` y `ADMIN_PASSWORD` desde Secret Manager. No
imprime la contraseña en logs.

## 5. Verificar Pub/Sub e IAM

```bash
gcloud pubsub topics describe mooc4-media-jobs
gcloud pubsub subscriptions describe mooc4-media-jobs-push
gcloud pubsub topics describe mooc4-media-jobs-dlq

gcloud run services get-iam-policy mooc4-worker --region us-central1
gcloud run services get-iam-policy mooc4-backend --region us-central1
gcloud run services get-iam-policy mooc4-frontend --region us-central1
```

Comprobaciones:

- `mooc4-worker`: solo `mooc4-pubsub-push` con `roles/run.invoker`; sin
  `allUsers`.
- `mooc4-backend` y `mooc4-frontend`: `allUsers` con `roles/run.invoker`.
- Suscripción push con `oidcToken.serviceAccountEmail = mooc4-pubsub-push` y
  audience igual a la URL del worker.
- Dead-letter y retry policy configurados.

## 6. Recorrido de una tarea

1. Abrir `frontend_url`, entrar como profesor, crear un curso y un recurso de
   video.
2. Subir un archivo. La UI muestra “Escaneando” → “Procesando” → “Disponible”.
3. Guardar `resource_id` y `task_id` de la respuesta de `upload-url` (si se usa
   la ruta legada) o seguir el recurso por `GET /api/v1/resources/:id`.
4. Consultar logs del backend y del worker con el `message_id`.
5. Verificar que el mensaje se confirma y que `num_undelivered_messages` vuelve
   a cero.

Comandos exactos en [operacion.md](operacion.md).

## 7. Reentrega idempotente

Después de que el recurso esté `ready`, publicar de nuevo el mismo mensaje:

```bash
gcloud pubsub topics publish mooc4-media-jobs \
  --message="{\"resource_id\":<ID>,\"object_key\":\"<OBJECT_KEY>\",\"mime_type\":\"video/mp4\",\"idempotency_key\":\"transcode-<STABLE_ID>\"}" \
  --attribute="type=media.transcode,idempotency_key=transcode-<STABLE_ID>"
```

El worker debe registrar `ya procesado (idempotente), skip`, responder 204 y no
crear objetos HLS nuevos. Guardar logs y listado del bucket.

## 8. Escalamiento

Desde la raíz del repositorio:

```bash
FRONTEND_URL="$(terraform -chdir=scripts/IaC/cloudrun output -raw frontend_url)" \
BACKEND_URL="$(terraform -chdir=scripts/IaC/cloudrun output -raw backend_url)" \
PROJECT_ID=proyecto-2-cloud-509714 \
./scripts/entrega4/verificar_escalamiento.sh
```

Para publicar tareas del worker en la misma corrida, añadir
`MESSAGES=9 RESOURCE_ID=<id> OBJECT_KEY=<key>`; usar recursos distintos si se
quiere observar tres workers ocupados. El script guarda series de
`run.googleapis.com/container/instance_count` y
`pubsub.googleapis.com/subscription/num_undelivered_messages` en
`docs/entrega4/evidencia/<fecha>/escalamiento/`.

Para el worker, publicar varias tareas reales con recursos distintos (no
duplicados) y observar:

- instancias de `mooc4-worker` de 0/1 a 3;
- `num_undelivered_messages` creciente mientras se saturan las 3 instancias;
- drenaje a cero al terminar;
- máximo configurado de 3 en la revisión.

La evidencia debe separar “límite configurado” de “instancias observadas”.

## 9. Evidencias

Desde la raíz del repositorio:

```bash
PROJECT_ID=proyecto-2-cloud-509714 \
./scripts/entrega4/capturar_evidencia.sh
```

Guardar en `docs/entrega4/evidencia/<fecha>/`:

- URLs de frontend y backend.
- Límites de los tres servicios.
- Políticas IAM.
- Topic, suscripción, OIDC, DLQ y retry.
- Listado de secretos sin valores.
- Logs de una tarea completa.
- Reentrega sin duplicados.
- Métricas de escalamiento.

## 10. Mailpit

```bash
gcloud compute ssh mooc4-support --zone us-central1-a --tunnel-through-iap \
  -- -L 8025:127.0.0.1:8025
# http://localhost:8025
```

## 11. Entorno local

```bash
docker compose -p mooc-local -f docker-compose.yml -f compose.dev.yml up -d --build
```

Compose levanta un emulador de Pub/Sub, crea el topic y una suscripción push al
worker local. El recorrido Playwright usa ese flujo. No hay asynq.

## 12. Retiro

`terraform destroy` requiere autorización explícita. Elimina Cloud SQL,
Memorystore, buckets (con `force_destroy`), secretos, VM y servicios Cloud Run.
No ejecutarlo como limpieza automática de pruebas.
