# Operación y evidencias — Entrega 4

## Seguir una tarea

El `message_id` que devuelve Pub/Sub queda en los logs del backend y del worker.
El `resource_id` permite consultar el estado persistido en PostgreSQL.

```bash
PROJECT=proyecto-2-cloud-509714
RESOURCE_ID=<id>

# Publicación (backend)
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="mooc4-backend" AND "pubsub"' \
  --project "$PROJECT" --limit 50 --format=json

# Entrega y finalización (worker)
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="mooc4-worker" AND "message_id"' \
  --project "$PROJECT" --limit 100 --format=json

# Estado persistido
curl -s "$BACKEND_URL/api/v1/resources/$RESOURCE_ID" \
  -H "Authorization: Bearer $TOKEN" | jq .
```

Estados esperados del recurso:

- `scan_status`: `pending` → `clean` (o `infected`).
- `processing_status`: `pending` → `processing` → `ready` (o `failed`).
- `hls_key`: `uploads/<stable_id>/index.m3u8` cuando el video está listo.

## Verificar la suscripción

```bash
gcloud pubsub subscriptions describe mooc4-media-jobs-push \
  --project proyecto-2-cloud-509714 --format=json
```

Comprobar `ackDeadlineSeconds=600`, `pushConfig.oidcToken`, `retryPolicy`,
`deadLetterPolicy` y `messageRetentionDuration`.

## Métricas de mensajes pendientes

```bash
PROJECT=proyecto-2-cloud-509714
TOKEN="$(gcloud auth print-access-token)"
START="$(python3 -c 'import datetime;print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=20)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
END="$(python3 -c 'import datetime;print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))')"

curl -sG "https://monitoring.googleapis.com/v3/projects/$PROJECT/timeSeries" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode 'filter=metric.type="pubsub.googleapis.com/subscription/num_undelivered_messages" AND resource.labels.subscription_id="mooc4-media-jobs-push"' \
  --data-urlencode "interval.startTime=$START" \
  --data-urlencode "interval.endTime=$END" > pendientes.json
```

Repetir con `run.googleapis.com/container/instance_count` y
`resource.labels.service_name` para cada servicio.

## Reentrega sin duplicados

Con un recurso ya `ready`, publicar el mismo transcode otra vez:

```bash
STABLE_ID=<stable_id>
OBJECT_KEY=<object_key>

gcloud pubsub topics publish mooc4-media-jobs \
  --project proyecto-2-cloud-509714 \
  --message="{\"resource_id\":$RESOURCE_ID,\"object_key\":\"$OBJECT_KEY\",\"mime_type\":\"video/mp4\",\"idempotency_key\":\"transcode-$STABLE_ID\"}" \
  --attribute="type=media.transcode,idempotency_key=transcode-$STABLE_ID"
```

Evidencia esperada:

- log `worker: recurso ... ya procesado (idempotente), skip`;
- respuesta 204 en Cloud Run;
- `processing_status=ready` sin cambios;
- el listado del bucket HLS no gana objetos nuevos.

Repetir para `media.scan` sobre un recurso `clean`: no vuelve a descargar ni a
escanear, y no republica un transcode si ya está `ready`.

## Dead-letter

Publicar un payload inválido o dejar que una tarea transitoria agote los
intentos:

```bash
gcloud pubsub topics publish mooc4-media-jobs \
  --project proyecto-2-cloud-509714 \
  --message='{"resource_id":0}' \
  --attribute="type=media.scan"

gcloud pubsub subscriptions pull mooc4-media-jobs-dlq-sub \
  --project proyecto-2-cloud-509714 --limit=5 --auto-ack
```

El mensaje debe aparecer en el DLQ tras 5 intentos y el recurso, si existe,
quedar `failed`.

## IAM

```bash
gcloud run services get-iam-policy mooc4-worker --region us-central1 --format=json
gcloud projects get-iam-policy proyecto-2-cloud-509714 \
  --flatten='bindings[].members' \
  --filter='bindings.members:mooc4-' --format=json
```

Comprobar:

- worker sin `allUsers`;
- `mooc4-pubsub-push` solo con `roles/run.invoker` sobre el worker;
- backend/worker con `pubsub.publisher` solo sobre el topic;
- cuentas con `secretAccessor` solo sobre sus secretos.

## Escalamiento

```bash
FRONTEND_URL="$(terraform -chdir=scripts/IaC/cloudrun output -raw frontend_url)" \
BACKEND_URL="$(terraform -chdir=scripts/IaC/cloudrun output -raw backend_url)" \
PROJECT_ID=proyecto-2-cloud-509714 \
./scripts/entrega4/verificar_escalamiento.sh
```

Registrar en la evidencia:

- fecha y hora UTC;
- número de solicitudes concurrentes;
- instancias observadas por servicio (mínimo/máximo);
- mensajes pendientes antes, durante y después;
- límite configurado de 3;
- si Cloud Run superó el máximo temporalmente, anotarlo como comportamiento de
  la plataforma, no como error de configuración.

## Mailpit

La UI se consulta en `https://<frontend_url>/mailpit/` con Basic Auth:

- usuario: `viewer`
- contraseña: `gcloud secrets versions access latest --secret=mooc4-mailpit-auth`

La VM no tiene IP pública. El frontend accede por la VPC; el firewall de Mailpit
solo acepta el puerto 8025 desde la etiqueta `frontend`. El SMTP (1025) sigue
privado para el backend.

## Limitaciones que deben quedar escritas

- Ack deadline máximo 600 s; ffmpeg 540 s.
- Memorystore Basic sin HA.
- VM de ClamAV/Mailpit como punto único de falla.
- Mailpit queda expuesto con Basic Auth a través del frontend; es una utilidad de prueba, no un servicio de correo de producción.
- Cloud SQL `db-f1-micro` con 25 conexiones.
- El frontend comparte su límite de 3 instancias con el tráfico de API.
