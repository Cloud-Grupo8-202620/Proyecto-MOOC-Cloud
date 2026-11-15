#!/usr/bin/env bash
# Arranque de la VM de soporte. Container-Optimized OS ya trae Docker; la VM
# solo aloja ClamAV y Mailpit. Redis es Memorystore y la mensajería es Pub/Sub.
set -Eeuo pipefail
exec > >(tee -a /var/log/mooc4-support-startup.log) 2>&1

for i in $(seq 1 30); do
  docker info >/dev/null 2>&1 && break
  sleep 2
done

echo "==> preparando volúmenes"
docker volume create mooc-clamav >/dev/null
docker volume create mooc-mailpit >/dev/null

echo "==> ClamAV"
docker rm -f mooc-clamav >/dev/null 2>&1 || true
docker run -d --name mooc-clamav --restart unless-stopped \
  --memory 1500m \
  -p 3310:3310 \
  -v mooc-clamav:/var/lib/clamav \
  clamav/clamav:stable

echo "==> Mailpit"
docker rm -f mooc-mailpit >/dev/null 2>&1 || true
docker run -d --name mooc-mailpit --restart unless-stopped \
  -p 1025:1025 -p 127.0.0.1:8025:8025 \
  -e MP_MAX_MESSAGES=5000 \
  -e MP_DATABASE=/data/mailpit.db \
  -e MP_SMTP_AUTH_ACCEPT_ANY=1 \
  -e MP_SMTP_AUTH_ALLOW_INSECURE=1 \
  -v mooc-mailpit:/data \
  axllent/mailpit

echo "==> soporte listo"
