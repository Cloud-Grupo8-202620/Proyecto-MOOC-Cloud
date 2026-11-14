# Cierre de la entrega 4

Completar únicamente con valores observados después del apply. No rellenar con
supuestos.

## Identificadores

| Campo | Valor |
|---|---|
| Proyecto | `proyecto-2-cloud-509714` |
| Región | `us-central1` |
| Rama | `entrega4-cloudrun-pubsub` |
| Commit | `<sha>` |
| Etiqueta de imágenes | `<image_tag>` |
| Fecha UTC del despliegue | `<fecha>` |
| URL frontend | `<frontend_url>` |
| URL backend | `<backend_url>` |
| URL worker | `<worker_url>` |
| Topic | `mooc4-media-jobs` |
| Suscripción push | `mooc4-media-jobs-push` |
| Dead-letter | `mooc4-media-jobs-dlq` |
| Evidencia | `docs/entrega4/evidencia/<fecha>/` |
| Video | `<enlace>` |

## Checklist de evidencias

- [ ] Tres servicios Cloud Run operativos y con URL.
- [ ] Imágenes en Artifact Registry con etiqueta inmutable.
- [ ] Límites: mínimo/máximo, CPU, memoria, concurrencia y timeout.
- [ ] Worker sin `allUsers`; solo `mooc4-pubsub-push` con `run.invoker`.
- [ ] Suscripción push con OIDC y audience del worker.
- [ ] Topic, suscripción, retry y DLQ documentados.
- [ ] Secretos listados sin valores; sin credenciales en repo ni imágenes.
- [ ] Recorrido de una tarea desde `publish` hasta `ready`.
- [ ] Acknowledgment después de persistir; `num_undelivered_messages` vuelve a 0.
- [ ] Reentrega del mismo mensaje sin duplicar HLS.
- [ ] Escalamiento observado: instancias y mensajes pendientes.
- [ ] Video de sustentación de máximo 20 minutos, con enlace accesible.
- [ ] Credenciales de prueba entregadas por el canal privado, no en el repo.

## Comandos de referencia

```bash
cd scripts/IaC/cloudrun
terraform output
gcloud run services list --region us-central1
gcloud pubsub subscriptions describe mooc4-media-jobs-push
gcloud run services get-iam-policy mooc4-worker --region us-central1
gcloud run jobs execute mooc4-provision-admin --region us-central1 --wait
```

## Decisiones

- Pub/Sub sustituye a asynq/Redis como mensajería.
- Redis queda solo para sesiones, códigos y locks TUS, en Memorystore.
- ClamAV y Mailpit quedan en una VM de soporte sin IP pública.
- El frontend hace proxy de la API para conservar el mismo origen.
- El worker se protege con IAM y OIDC, no con una URL secreta.
