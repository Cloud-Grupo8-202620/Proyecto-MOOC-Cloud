#!/usr/bin/env bash
set -u; cd "$(dirname "$0")"
echo "[$(date -u +%FT%TZ)] == Escenario 3A (API) PEAK_RATE=8"
env PEAK_RATE=8 ./run_e3.sh 3a-r2 'nada*' esc3:api
echo "[$(date -u +%FT%TZ)] == integridad"
./run_e3.sh e1-integridad-r2 'integridad*' integridad
