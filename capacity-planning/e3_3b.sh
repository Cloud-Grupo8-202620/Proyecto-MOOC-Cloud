#!/usr/bin/env bash
set -u; cd "$(dirname "$0")"
echo "[$(date -u +%FT%TZ)] == Escenario 3B (workers)"
./run_e3.sh 3b-r1 'nada*' esc3:workers
