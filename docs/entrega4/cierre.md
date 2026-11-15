# Cierre de la entrega 4

## Identificadores

| Campo | Valor |
|---|---|
| Proyecto | `proyecto-2-cloud-509714` |
| Región | `us-central1` |
| Rama | `entrega4-cloudrun-pubsub` |
| Commit de la imagen | `b8f32af` |
| Etiqueta de imágenes | `b8f32af9643a` |
| Fecha UTC del despliegue | `2026-11-15` |
| URL frontend | https://mooc4-frontend-e5xkihk7sa-uc.a.run.app |
| URL backend | https://mooc4-backend-e5xkihk7sa-uc.a.run.app |
| URL worker | https://mooc4-worker-e5xkihk7sa-uc.a.run.app |
| Topic | `mooc4-media-jobs` |
| Suscripción push | `mooc4-media-jobs-push` |
| Dead-letter | `mooc4-media-jobs-dlq` |
| Evidencia vigente | [RESUMEN-2026-11-15.md](evidencia/RESUMEN-2026-11-15.md) |
| Evidencia histórica | [RESUMEN-2026-11-14.md](evidencia/RESUMEN-2026-11-14.md) |
| Video | `<pendiente>` |
| Escalamiento | 0–3 en frontend, backend y worker; máximo 3 a nivel de servicio |

## Checklist de evidencias

- [x] Tres servicios Cloud Run operativos y con URL.
- [x] Imágenes en Artifact Registry con etiqueta inmutable `b8f32af9643a`.
- [x] Límites: mínimo/máximo, CPU, memoria, concurrencia y timeout.
- [x] Worker sin `allUsers`; solo `mooc4-pubsub-push` con `run.invoker`.
- [x] Suscripción push con OIDC y audience del worker.
- [x] Topic, suscripción, retry y DLQ documentados.
- [x] Secretos listados sin valores; sin credenciales en repo ni imágenes.
- [x] Recorrido de una tarea desde `publish` hasta `ready`.
- [x] Acknowledgment después de persistir; `num_undelivered_messages` vuelve a 0.
- [x] Reentrega del mismo mensaje sin duplicar HLS.
- [x] Escalamiento observado: worker y backend a 3; frontend a 2 con máximo 3.
- [x] Recorrido Playwright completo contra Cloud Run (**1.8 min**).
- [x] ClamAV en la VM de soporte `healthy`; límite de memoria corregido a 3 GB.
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

El administrador inicial es `admin`; la contraseña está en el secreto
`mooc4-admin-password` y no se versiona. Entregarla por el canal privado.

## Decisiones

- Pub/Sub sustituye a asynq/Redis como mensajería.
- Redis queda solo para sesiones, códigos y locks TUS, en Memorystore.
- ClamAV y Mailpit quedan en una VM de soporte sin IP pública.
- El frontend hace proxy de la API para conservar el mismo origen.
- El worker se protege con IAM y OIDC, no con una URL secreta.
