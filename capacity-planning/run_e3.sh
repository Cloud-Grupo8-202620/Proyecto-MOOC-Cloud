#!/usr/bin/env bash
set -uo pipefail
RUN_ID="$1"; GLOB="$2"; shift 2
OUT="results/entrega3/${RUN_ID}"
mkdir -p "${OUT}"
[ -e "${OUT}/meta.json" ] && { echo "RUN_ID ${RUN_ID} ya existe; use otro" >&2; exit 2; }
START="$(date -u +%FT%TZ)"
export RUN_ID
task "$@" >"${OUT}/task.log" 2>&1
RC=$?
END="$(date -u +%FT%TZ)"
shopt -s nullglob
for f in results/${GLOB}; do mv "$f" "${OUT}/"; done
cat >"${OUT}/meta.json" <<JSON
{"run_id":"${RUN_ID}","start_utc":"${START}","end_utc":"${END}","exit_code":${RC},
 "task":"$*","base_url":"${BASE_URL:-}","k6":"$(k6 version | head -1)","generator":"$(hostname) $(nproc)vCPU",
 "git":"$(git -C .. -c safe.directory='*' rev-parse --short HEAD 2>/dev/null)"}
JSON
sed -i -E 's/(ADMIN_PASS|SEED_PASSWORD)=[^ ]+/\1=***/g' "${OUT}/task.log"
echo "${RUN_ID} rc=${RC} ${START} -> ${END}"
