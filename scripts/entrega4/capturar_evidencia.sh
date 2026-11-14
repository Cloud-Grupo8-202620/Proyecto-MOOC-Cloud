#!/usr/bin/env bash
# Captura el estado del despliegue y las políticas de acceso. No descarga
# valores de secretos.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-proyecto-2-cloud-509714}"
REGION="${REGION:-us-central1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IAC_DIR="${ROOT}/scripts/IaC/cloudrun"
OUT="${1:-${ROOT}/docs/entrega4/evidencia/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "${OUT}/servicios" "${OUT}/iam" "${OUT}/pubsub" "${OUT}/logs"

echo "==> ${OUT}"

for s in mooc4-frontend mooc4-backend mooc4-worker; do
  gcloud run services describe "$s" --project "$PROJECT_ID" --region "$REGION" \
    --format=json > "${OUT}/servicios/${s#mooc4-}.json"
  gcloud run services get-iam-policy "$s" --project "$PROJECT_ID" --region "$REGION" \
    --format=json > "${OUT}/iam/${s#mooc4-}.json"
done

gcloud pubsub topics describe mooc4-media-jobs --project "$PROJECT_ID" \
  --format=json > "${OUT}/pubsub/topic.json"
gcloud pubsub subscriptions describe mooc4-media-jobs-push --project "$PROJECT_ID" \
  --format=json > "${OUT}/pubsub/subscription.json"
gcloud pubsub topics describe mooc4-media-jobs-dlq --project "$PROJECT_ID" \
  --format=json > "${OUT}/pubsub/dlq.json"

# Solo nombres y metadatos; nunca versiones ni valores.
gcloud secrets list --project "$PROJECT_ID" --filter='name~mooc4-' --format=json \
  > "${OUT}/secretos.json"
gcloud iam service-accounts list --project "$PROJECT_ID" \
  --filter='email~^mooc4-' --format=json > "${OUT}/service-accounts.json"
gcloud projects get-iam-policy "$PROJECT_ID" --format=json > "${OUT}/project-iam.json"

terraform -chdir="${IAC_DIR}" output -json > "${OUT}/despliegue.json" 2>/dev/null || true

# Últimos logs de los tres servicios; sirven para localizar un message_id.
for s in backend worker frontend; do
  gcloud logging read \
    "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"mooc4-${s}\"" \
    --project "$PROJECT_ID" --limit 200 --format=json \
    > "${OUT}/logs/${s}.json" 2>/dev/null || echo '[]' > "${OUT}/logs/${s}.json"
done

python3 - "${OUT}" <<'PY'
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
resumen = {}
for name in ("frontend", "backend", "worker"):
    d = json.loads((out / "servicios" / f"{name}.json").read_text())
    template = d.get("spec", {}).get("template", {})
    spec = template.get("spec", {})
    annotations = template.get("metadata", {}).get("annotations", {})
    c = (spec.get("containers") or [{}])[0]
    res = (c.get("resources") or {}).get("limits") or {}
    scaling = spec.get("scaling") or {}
    # gcloud puede devolver la forma v1 (containerConcurrency/timeoutSeconds y
    # anotaciones de autoscaling) o la forma v2.
    resumen[name] = {
        "url": d.get("status", {}).get("url"),
        "min_instance_count": scaling.get("minInstanceCount", annotations.get("autoscaling.knative.dev/minScale")),
        "max_instance_count": scaling.get("maxInstanceCount", annotations.get("autoscaling.knative.dev/maxScale")),
        "container_concurrency": spec.get("maxInstanceRequestConcurrency", spec.get("containerConcurrency")),
        "timeout_seconds": spec.get("timeout", spec.get("timeoutSeconds")),
        "cpu": res.get("cpu"),
        "memory": res.get("memory"),
    }
(out / "limites.json").write_text(json.dumps(resumen, indent=2, ensure_ascii=False) + "\n")
PY

echo "==> evidencia guardada en ${OUT}"
