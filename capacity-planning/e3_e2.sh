#!/usr/bin/env bash
set -u; cd "$(dirname "$0")"; R=./run_e3.sh
echo "[$(date -u +%FT%TZ)] == Escenario 2"
$R e2-carga-M0 'esc2-carga-M0*' esc2:carga LEVEL=M0
$R e2-carga-M1 'esc2-carga-M1*' esc2:carga LEVEL=M1
$R e2-carga-M2 'esc2-carga-M2*' esc2:carga LEVEL=M2
$R e2-tus 'esc2-tus*' esc2:tus
$R e2-consumo-reproduccion 'esc2-consumo*' esc2:consumo PATRON=reproduccion
$R e2-consumo-burst 'esc2-consumo*' esc2:consumo PATRON=burst
$R e2-drenaje 'esc2-drenaje*' esc2:drenaje DURACION=20m DURACION_MIN=20
