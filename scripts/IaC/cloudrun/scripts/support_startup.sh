#!/usr/bin/env bash
# Arranque de la VM de soporte. Container-Optimized OS ya trae Docker; la VM
# solo aloja ClamAV y Mailpit. Redis es Memorystore y la mensajería es Pub/Sub.
set -Eeuo pipefail
exec > >(tee -a /var/log/mooc4-support-startup.log) 2>&1

for i in $(seq 1 30); do
  docker info >/dev/null 2>&1 && break
  sleep 2
done

meta() {
  curl -fsS -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/$1"
}

# Mailpit queda detrás del proxy HTTPS del frontend (/mailpit/) y protegido con
# Basic Auth. La credencial se lee de Secret Manager; nunca se escribe en el
# metadata ni en la imagen.
PROJECT_ID="$(meta project/project-id)"
SECRET_NAME="$(meta instance/attributes/mailpit-auth-secret)"
TOKEN="$(meta instance/service-accounts/default/token | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"
SECRET_JSON="$(curl -fsS -H "Authorization: Bearer ${TOKEN}" \
  "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/${SECRET_NAME}/versions/latest:access")"
MAILPIT_UI_PASSWORD="$(printf '%s' "${SECRET_JSON}" | tr -d '[:space:]' | sed -n 's/.*"data":"\([^"]*\)".*/\1/p' | base64 -d)"
[ -n "${MAILPIT_UI_PASSWORD}" ] || { echo "no se pudo leer la contraseña de Mailpit" >&2; exit 1; }
MAILPIT_UI_AUTH="viewer:${MAILPIT_UI_PASSWORD}"

echo "==> preparando volúmenes"
docker volume create mooc-clamav >/dev/null
docker volume create mooc-mailpit >/dev/null

echo "==> ClamAV"
docker rm -f mooc-clamav >/dev/null 2>&1 || true
docker run -d --name mooc-clamav --restart unless-stopped \
  --memory 3g \
  -p 3310:3310 \
  -v mooc-clamav:/var/lib/clamav \
  clamav/clamav:stable

echo "==> Mailpit"
docker rm -f mooc-mailpit >/dev/null 2>&1 || true
docker run -d --name mooc-mailpit --restart unless-stopped \
  -p 1025:1025 -p 8025:8025 \
  -e MP_MAX_MESSAGES=5000 \
  -e MP_DATABASE=/data/mailpit.db \
  -e MP_UI_AUTH="${MAILPIT_UI_AUTH}" \
  -e MP_WEBROOT=/mailpit/ \
  -e MP_SMTP_AUTH_ACCEPT_ANY=1 \
  -e MP_SMTP_AUTH_ALLOW_INSECURE=1 \
  -v mooc-mailpit:/data \
  axllent/mailpit

echo "==> soporte listo"
