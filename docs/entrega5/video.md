# Video de sustentación — Entrega 5

Enlace (acceso para el evaluador): **PENDIENTE — pegar aquí el enlace tras grabarlo** (máximo 20 minutos).

## Guion sugerido (≈ 15 min)

1. **Análisis (3 min)** — [analisis-serverless.md](analisis-serverless.md): qué ya es serverless, tabla de oportunidades, por qué se eligió `media.scan`.
2. **Migración (4 min)** — diagrama de [arquitectura.md](arquitectura.md); mostrar `backend/scanner`, `backend/functions/scanfn`, el worker sin la rama de escaneo y `queue.EnqueueScan` apuntando al topic nuevo; explicar reintentos e idempotencia.
3. **Terraform (4 min)** — `terraform init`, `plan` y `apply` (o actualización sobre un despliegue existente); recorrer `functions.tf`, `pubsub.tf`, `iam.tf`; mostrar que no hay secretos ni estado en el repo.
4. **Tarea real (4 min)** — subir un video o `scripts/entrega5/probar_scan.sh`: mensaje en Pub/Sub, logs de la función, `scan_status=clean` en la API, transcode en el worker; republicar el mensaje y mostrar que no hay efectos duplicados.
