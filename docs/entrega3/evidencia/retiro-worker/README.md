# Retiro controlado de un worker con trabajo activo (durante 3B, 2026-11-01)

- 23:30:33 UTC: `gcloud compute instance-groups managed delete-instances mooc-worker-mig --instances=mooc-worker-hbnf`.
  El worker tenía 4 transcodificaciones ffmpeg activas (recursos 1102, 1107, 1108, 1109; ver `01-antes-*.txt`).
- Las 4 tareas se reentregaron y terminaron en `mooc-worker-xk16` (HLS listo): 1108 a las 23:34:43, 1107 a las 23:34:50,
  1102 a las 23:39:17 y 1109 a las 23:39:22 (`03-despues-reentrega.txt`).
- Retraso de recuperación: 4 a 9 min desde el retiro hasta el HLS listo.
- Esta prueba manual NO reemplaza la reducción automática de 3B; el ciclo de 3B incluye esta intervención y se anota así.
- Pendiente: confirmar con `reconciliar_trabajos.py` que no hay objetos duplicados ni recursos fallidos.
