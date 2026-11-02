#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"
RUN="$1"; OUT="results/entrega3/${RUN}"
TOKEN="$(curl -s -X POST "${BASE_URL}/api/v1/auth/login" -H 'Content-Type: application/json' \
  -d "{\"username\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASS}\"}" | jq -r .token)"
export ADMIN_TOKEN="${TOKEN}"
for i in $(seq 1 24); do
  rm -f "${OUT}/reconciliation.json"
  if python3 reconciliar_trabajos.py --manifest "${OUT}/accepted.jsonl" --output "${OUT}/reconciliation.json"; then
    echo "reconciliación completa en el intento ${i}"; exit 0
  fi
  echo "intento ${i}: aún hay trabajos sin terminar; se reintenta en 5 min"; sleep 300
done
echo "reconciliación incompleta tras 24 intentos (ver reconciliation.json)"; exit 1
