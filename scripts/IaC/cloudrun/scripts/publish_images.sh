#!/usr/bin/env bash
# Construye y publica frontend, backend y worker en Artifact Registry.
#
# Uso, desde scripts/IaC/cloudrun:
#   terraform apply -target=google_artifact_registry_repository.images
#   ./scripts/publish_images.sh
#   # poner la etiqueta en terraform.tfvars y ejecutar terraform apply
#
# Variables opcionales:
#   PROJECT_ID     proyecto (por defecto, terraform output o gcloud config)
#   REGION         región del registro (por defecto us-central1)
#   REPOSITORY     repositorio (por defecto mooc4-images)
#   IMAGE_TAG      etiqueta a publicar (por defecto, commit corto)
#   SKIP_FRONTEND  true para no construir el frontend
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IAC_DIR="$(dirname "${SCRIPT_DIR}")"
REPO_ROOT="$(git -C "${IAC_DIR}" rev-parse --show-toplevel)"

tf_output() { terraform -chdir="${IAC_DIR}" output -raw "$1" 2>/dev/null || true; }

REGION="${REGION:-us-central1}"
REPOSITORY="${REPOSITORY:-mooc4-images}"
PLATFORM="${PLATFORM:-linux/amd64}"
SKIP_FRONTEND="${SKIP_FRONTEND:-false}"

IMAGE_REPO="$(tf_output image_repository)"
if [[ -z "${IMAGE_REPO}" || "${IMAGE_REPO}" == *"Warning"* ]]; then
  PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
  [[ -n "${PROJECT_ID}" ]] || { echo "No hay PROJECT_ID: expórtalo o configura gcloud" >&2; exit 1; }
  IMAGE_REPO="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}"
fi
REGISTRY_HOST="${IMAGE_REPO%%/*}"

if [[ -z "${IMAGE_TAG:-}" ]]; then
  IMAGE_TAG="$(git -C "${REPO_ROOT}" rev-parse --short=12 HEAD)"
  if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain -- backend frontend)" ]]; then
    IMAGE_TAG="${IMAGE_TAG}-dirty-$(date -u +%Y%m%d%H%M%S)"
  fi
fi

echo "==> registro  ${IMAGE_REPO}"
echo "==> etiqueta  ${IMAGE_TAG}"
echo "==> destino   ${PLATFORM}"

gcloud auth configure-docker "${REGISTRY_HOST}" --quiet >/dev/null 2>&1

exists() {
  gcloud artifacts docker images describe "$1" >/dev/null 2>&1
}

build() {
  local name="$1" context="$2" dockerfile="$3"
  local ref="${IMAGE_REPO}/${name}:${IMAGE_TAG}"
  if exists "${ref}"; then
    echo "==> ${name}: ${ref} ya existe, se reutiliza"
    return 0
  fi
  echo "==> ${name}: construyendo ${ref}"
  docker buildx build --platform "${PLATFORM}" \
    -f "${dockerfile}" -t "${ref}" --push "${context}"
}

build backend "${REPO_ROOT}/backend" "${REPO_ROOT}/backend/Dockerfile"
build worker "${REPO_ROOT}/backend" "${REPO_ROOT}/backend/worker/Dockerfile"
if [[ "${SKIP_FRONTEND}" != "true" ]]; then
  build frontend "${REPO_ROOT}/frontend" "${REPO_ROOT}/frontend/Dockerfile"
else
  echo "==> frontend: omitido (SKIP_FRONTEND=true)"
fi

echo
echo "Imágenes publicadas. En terraform.tfvars:"
echo "  image_tag = \"${IMAGE_TAG}\""
echo "IMAGE_TAG=${IMAGE_TAG}"
