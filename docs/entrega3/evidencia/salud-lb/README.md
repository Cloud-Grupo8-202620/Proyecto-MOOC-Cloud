# Prueba de salud del balanceador y autohealing (API)

Corrida: durante `3a-r1` (escenario 3A), 2026-11-01. Con 3 APIs sanas se detuvo solo el contenedor
`mooc-api` de `mooc-api-xj02` (`docker stop`). No se tocó la VM ni las otras dos APIs.

| UTC | Evento |
|---|---|
| 23:11:45 | `docker stop mooc-api` en mooc-api-xj02 |
| 23:12:21 | MIG: `compute.instances.repair.recreateInstance` (autohealing) |
| 23:12:38 | Primera muestra con xj02 UNHEALTHY en el backend (muestreo cada ~12 s) |
| 23:13:48 | xj02 sale del backend mientras se recrea |
| 23:14:48 | Reaparece UNHEALTHY (VM nueva arrancando) |
| 23:15:39 | xj02 HEALTHY |

- `/health` por el LB respondió 200 en las 18 muestras: el tráfico siguió en las otras dos APIs.
- Límite: el muestreo no separa con precisión la exclusión del LB del inicio de la reparación del MIG
  (ambos usan el health check); el instante exacto de la exclusión por el LB queda acotado a 23:11:50-23:12:38.
- Esta corrida de 3A tuvo una intervención manual; `3a-r2` es la corrida limpia.
