# Evidencias — Entrega 5

Las evidencias se capturan **después de desplegar** con las instrucciones de [despliegue.md](../despliegue.md). Cada carpeta lleva marca de tiempo UTC. No se versionan estado, `tfvars` ni valores de secretos.

| # | Evidencia | Cómo se genera | Qué demuestra |
|---|---|---|---|
| 1 | `terraform-init-plan-apply.txt` | `terraform init`, `plan -out`, `apply` con `\| tee` | Despliegue reproducible de Cloud Run, Pub/Sub, función, IAM y secretos |
| 2 | `terraform-actualizacion.txt` | Cambiar `scan_fn_max_instances` o el código y volver a `plan`/`apply` | Las actualizaciones son incrementales |
| 3 | `terraform-output.json` | `terraform output -json` | Nombres de función, topic, URLs |
| 4 | `<fecha>-scan/` | `scripts/entrega5/probar_scan.sh` (con `REPUBLISH=1`) | Mensaje real: Pub/Sub → función → resultado; reentrega sin duplicados |
| 5 | `funcion.json`, `gcloud-iam-*.json` | `gcloud functions describe`, `gcloud run services get-iam-policy` | Disparador, cuentas y permisos mínimos |
| 6 | Estado del recurso por la API | `GET /api/v1/resources/<id>` antes y después | `scan_status=clean`, `processing_status=ready`, HLS generado |
| 7 | `logs-worker.txt` | Mismo script | El worker no registra `scan recibido` |

Estado: **pendiente de captura** (requiere el despliegue real en el proyecto de GCP).
