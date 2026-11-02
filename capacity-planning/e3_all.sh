#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"
R=./run_e3.sh
log() { echo "[$(date -u +%FT%TZ)] $*"; }

log "== Escenario 1"
$R e1-L0 'esc1-L0*' esc1:level LEVEL=L0
$R e1-L1 'esc1-L1*' esc1:level LEVEL=L1
$R e1-L2 'esc1-L2*' esc1:level LEVEL=L2
$R e1-L3-r1 'esc1-L3*' esc1:level LEVEL=L3
$R e1-L4 'esc1-L4*' esc1:level LEVEL=L4
$R e1-L3-r2 'esc1-L3*' esc1:level LEVEL=L3
$R e1-L3-r3 'esc1-L3*' esc1:level LEVEL=L3
$R e1-login-burst 'esc1-login*' esc1:burst
$R e1-integridad 'integridad*' integridad
$R e1-T1 'esc1-T1*' esc1:level LEVEL=T1 SIN_PAUSA=true SIN_ABORTAR=true
