#!/usr/bin/env bash
# Carga controlada para observar escalamiento de frontend/backend y, si se
# indican RESOURCE_ID/OBJECT_KEY, publica tareas de escaneo para el worker.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-proyecto-2-cloud-509714}"
REGION="${REGION:-us-central1}"
FRONTEND_URL="${FRONTEND_URL:?Define FRONTEND_URL}"
BACKEND_URL="${BACKEND_URL:?Define BACKEND_URL}"
N="${N:-120}"
PARALLEL="${PARALLEL:-40}"
MESSAGES="${MESSAGES:-0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-${ROOT}/docs/entrega4/evidencia/$(date -u +%Y%m%dT%H%M%SZ)/escalamiento}"
mkdir -p "$OUT"

echo "==> solicitudes concurrentes: ${N} (paralelo ${PARALLEL})"
{
  echo "fecha_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "frontend_url=${FRONTEND_URL}"
  echo "backend_url=${BACKEND_URL}"
  echo "n=${N}"
  echo "parallel=${PARALLEL}"
} > "${OUT}/resumen.txt"

seq "$N" | xargs -P "$PARALLEL" -I{} curl -s -o /dev/null -w '%{http_code}\n' "${FRONTEND_URL}/" \
  > "${OUT}/frontend-http.txt" || true
seq "$N" | xargs -P "$PARALLEL" -I{} curl -s -o /dev/null -w '%{http_code}\n' "${BACKEND_URL}/health" \
  > "${OUT}/backend-http.txt" || true

if [[ "$MESSAGES" -gt 0 && -n "${RESOURCE_ID:-}" && -n "${OBJECT_KEY:-}" ]]; then
  echo "==> publicando ${MESSAGES} tareas de escaneo"
  for i in $(seq 1 "$MESSAGES"); do
    gcloud pubsub topics publish mooc4-media-jobs --project "$PROJECT_ID" \
      --message="{\"resource_id\":${RESOURCE_ID},\"object_key\":\"${OBJECT_KEY}\",\"transcode_key\":\"transcode-${RESOURCE_ID}\"}" \
      --attribute=type=media.scan \
      --attribute=idempotency_key="scan-${RESOURCE_ID}-${i}" >/dev/null
  done
fi

TOKEN="$(gcloud auth print-access-token)"
START="$(python3 -c 'import datetime;print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=15)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
END="$(python3 -c 'import datetime;print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))')"

series() {
  local filter="$1" dest="$2"
  curl -sG "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/timeSeries" \
    -H "Authorization: Bearer ${TOKEN}" \
    --data-urlencode "filter=${filter}" \
    --data-urlencode "interval.startTime=${START}" \
    --data-urlencode "interval.endTime=${END}" \
    --data-urlencode "aggregation.alignmentPeriod=60s" \
    --data-urlencode "aggregation.perSeriesAligner=ALIGN_MAX" \
    > "${dest}"
}

series "metric.type=\"run.googleapis.com/container/instance_count\" AND resource.type=\"cloud_run_revision\"" \
  "${OUT}/instancias.json"
series "metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\" AND resource.labels.subscription_id=\"mooc4-media-jobs-push\"" \
  "${OUT}/pendientes.json"

echo "==> evidencia en ${OUT}"
echo "Revisar instancias.json y pendientes.json; anotar el máximo observado por servicio."
