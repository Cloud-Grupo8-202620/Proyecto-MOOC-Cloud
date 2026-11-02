# Evidencia — banco de pruebas `mooc-entrega3` (2026-11-02)

Entorno: `mooc-entrega3`, <https://8.232.5.195.sslip.io>, imagen `ad21fb9562a7`, 3 API + 3 workers
forzados con `min=3`. **No es el entorno evaluado** (`proyecto-2-cloud-509714`), sino el banco de
pruebas con la misma imagen. Se conserva para no perder las verificaciones hechas con el plazo encima.

## Frontend

`E2E_MEDIA=false python3 scripts/test_browser.py` con `E2E_BASE_URL` apuntando al banco:
**1 recorrido aprobado (19,3 s)**. Cubre estado vacío, error de credenciales, autoría de curso, módulo,
unidad, lectura, quiz con un intento, edición de pregunta, publicación, inscripción, consumo de texto,
progreso, envío del quiz y nota persistente; más las negativas de autorización. Capturas:
`profesor-*.png`, `estudiante-*.png`, `estudiante-movil-*.png` y `e2e.log`.

**Bloqueo encontrado con medios**: el recorrido completo (video, PDF, imagen y audio) falló dos veces
esperando `Disponible`. El worker registra:

```
ALERT worker task=media:scan archived/failed retry=0
err=descarga original: The specified key does not exist.
payload={"resource_id":559,"object_key":"uploads/.../p1-small.mp4"}
```

El objeto aparece en GCS a las 01:16:51 y el worker lo intentó a las 01:16:49: es la carrera entre la
autorización de la carga y el PUT, ya registrada como deuda DT-03. El flujo académico no está afectado.
El curso 30 del banco sí tiene audio `clean`/`ready` con HLS, subido antes de esta prueba.

## Integridad (`integridad/api.json`, `retiro-api.txt`)

| Verificación | Resultado |
|---|---|
| Sesión entre réplicas | 30/30 respuestas 200 con el mismo token; reparto `ms2r` 11, `2g7v` 11, `j5pn` 8 |
| Intento duplicado | Dos `submit` del mismo intento: mismo `score` (50) y `status` (`submitted`) |
| Archivos desde cualquier instancia | 20/20 `download-url` con 200 y una sola URL firmada |
| Retiro de API | Contenedor detenido en `ms2r`; el LB lo marcó `UNHEALTHY` y las 20 peticiones siguientes (200) fueron a las otras dos réplicas. El MIG reinició la instancia a las 01:32:17 y volvió a `HEALTHY` a las 01:33:44 (~3 min) |
| Retiro de worker con trabajo activo | Pendiente: la cola estaba vacía y la carrera de carga impidió generar un trabajo nuevo |

## Reproducir

```bash
gcloud compute instance-groups managed set-autoscaling mooc-api-mig --zone us-central1-a \
  --project mooc-entrega3 --min-num-replicas=3 --max-num-replicas=3 --target-cpu-utilization=0.6
cd frontend
E2E_MEDIA=false E2E_BASE_URL=https://8.232.5.195.sslip.io \
  E2E_ADMIN_USER=<admin> E2E_ADMIN_PASSWORD=<clave> pnpm exec playwright test
```
