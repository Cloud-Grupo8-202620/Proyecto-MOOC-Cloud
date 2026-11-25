#!/usr/bin/env bash
# Evidencia de entrega 5: publica un mensaje real en el topic de escaneo y
# registra el recorrido Pub/Sub -> Eventarc -> Cloud Function -> Cloud SQL ->
# transcode. No imprime secretos.
#
# Uso:
#   RESOURCE_ID=<id> OBJECT_KEY=<clave en originals> [TRANSCODE_KEY=...] \
#     scripts/entrega5/probar_scan.sh [directorio-de-salida]
# El recurso debe existir (subido por la API o TUS). REPUBLISH=1 publica un
# segundo mensaje idéntico para demostrar que no hay efectos duplicados.
set -euo pipefail

: "${RESOURCE_ID:?RESOURCE_ID requerido}"
: "${OBJECT_KEY:?OBJECT_KEY requerido}"
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${REGION:-us-central1}"
PREFIX="${PREFIX:-mooc4}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-${ROOT}/docs/entrega5/evidencia/$(date -u +%Y%m%dT%H%M%SZ)-scan}"
mkdir -p "${OUT}"
TOPIC="${PREFIX}-media-scan"
FN="${PREFIX}-scan-media"
PAYLOAD="{\"resource_id\":${RESOURCE_ID},\"object_key\":\"${OBJECT_KEY}\",\"transcode_key\":\"${TRANSCODE_KEY:-transcode-prueba-${RESOURCE_ID}}\"}"

publish() {
  gcloud pubsub topics publish "${TOPIC}" --project "${PROJECT_ID}" \
    --attribute="type=media.scan,idempotency_key=scan-prueba-${RESOURCE_ID}" \
    --message="${PAYLOAD}" --format=json
}

echo "==> publicando en ${TOPIC}"
publish | tee "${OUT}/publicacion.json"
if [[ "${REPUBLISH:-0}" == "1" ]]; then
  echo "==> reentrega: mismo mensaje otra vez"
  publish | tee "${OUT}/publicacion-reentrega.json"
fi

echo "==> esperando a la función (45 s)"
sleep 45
gcloud functions describe "${FN}" --gen2 --region "${REGION}" --project "${PROJECT_ID}" \
  --format=json > "${OUT}/funcion.json"
gcloud logging read \
  "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${FN}\" AND textPayload:\"scanfn:\"" \
  --project "${PROJECT_ID}" --freshness=10m --limit 50 --format='value(timestamp,textPayload)' \
  | sort > "${OUT}/logs-funcion.txt"
gcloud logging read \
  "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${PREFIX}-worker\" AND textPayload:\"worker:\"" \
  --project "${PROJECT_ID}" --freshness=10m --limit 50 --format='value(timestamp,textPayload)' \
  | sort > "${OUT}/logs-worker.txt"
cat "${OUT}/logs-funcion.txt"
echo "==> el estado final (scan_status/processing_status) se consulta por la API: GET /api/v1/resources/${RESOURCE_ID}"
echo "Evidencia en ${OUT}"
