# Plataforma MOOC — Entrega 4, ISIS4426

API Go + workers asíncronos, frontend React/Vite, PostgreSQL, Memorystore, ClamAV y almacenamiento de objetos, desplegados como **tres servicios Cloud Run** con **Pub/Sub** como mecanismo de mensajería. El frontend es nginx y hace proxy de la API para conservar el mismo origen.

**Estado:** **redesplegado y verificado el 2026-11-15** con la imagen `060d840f5c48`. Frontend, backend y worker están operativos; ClamAV quedó healthy tras corregir su límite de memoria. Evidencia vigente en [RESUMEN-2026-11-15](docs/entrega4/evidencia/RESUMEN-2026-11-15.md).

> **Entrega 5 (Cloud Function + Terraform):** la tarea `media.scan` se migró a una Cloud Run function de segunda generación disparada por Pub/Sub. Ver [análisis serverless](docs/entrega5/analisis-serverless.md), [arquitectura](docs/entrega5/arquitectura.md), [despliegue con Terraform](docs/entrega5/despliegue.md), [evidencias](docs/entrega5/evidencia/README.md) y [video](docs/entrega5/video.md).

- Frontend: <https://mooc4-frontend-e5xkihk7sa-uc.a.run.app>
- Backend: <https://mooc4-backend-e5xkihk7sa-uc.a.run.app>
- Mailpit: <https://mooc4-frontend-e5xkihk7sa-uc.a.run.app/mailpit/> (usuario `viewer`; contraseña en `mooc4-mailpit-auth`)

## Arquitectura

```
Navegador → Cloud Run frontend (0–3) → proxy /api → Cloud Run backend (0–3)
                                                      │ publish
                                                      ▼
                                                Pub/Sub topic
                                                      │ push OIDC
                                                      ▼
                                                Cloud Run worker (0–3)
Backend/worker → Cloud SQL · Cloud Storage · Memorystore Redis
Worker → ClamAV (VM de soporte) · Backend → Mailpit (VM de soporte)
```

- Máximo configurado: **3 instancias por servicio**, un contenedor por instancia.
- Worker privado: solo `mooc4-pubsub-push` tiene `run.invoker`; no hay `allUsers`.
- Secretos en Secret Manager; sin credenciales en el repositorio ni en las imágenes.
- Ack de Pub/Sub después de persistir; dead-letter a los 5 intentos y reentregas idempotentes.

## Documentación de entrega 4

- [Arquitectura y decisiones](docs/entrega4/arquitectura.md), con [diagramas](docs/entrega4/diagramas/).
- [Guía de despliegue reproducible](docs/entrega4/despliegue.md).
- [Operación, logs, reentrega y escalamiento](docs/entrega4/operacion.md).
- [Cierre y checklist](docs/entrega4/cierre.md).
- [Terraform Cloud Run](scripts/IaC/cloudrun/README.md).
- [Evidencias](docs/entrega4/evidencia/README.md).

## Desarrollo local

Requiere Docker Compose reciente con soporte `!override`/`!reset`. Crear `.env` desde `.env.example`; las credenciales de ejemplo son solo locales.

```bash
# Desde la raíz; conserva los datos existentes.
docker compose -p mooc-local -f docker-compose.yml -f compose.dev.yml up -d --build
```

Compose levanta el emulador de Pub/Sub, crea el topic y la suscripción push al worker, además de PostgreSQL, Redis, MinIO/RustFS, ClamAV y Mailpit. Abrir <http://localhost:5180> o <http://mooc.localhost:5180>. El frontend conecta con la API por el proxy de Vite.

El registro público solo permite estudiantes. Para preparar un administrador local:

```bash
docker exec -i mooc-local-backend-1 ./main provision-admin <<'JSON'
{"username":"admin","email":"admin@test.invalid","password":"una-contraseña-de-12-a-72-bytes"}
JSON
```

La contraseña no debe quedar en argumentos, repositorio ni logs.

## Verificación

GitHub Actions ejecuta Go con race detector, integración PostgreSQL/Redis, build TypeScript/Vite, recorrido de navegador con Pub/Sub local, Terraform con mocks (IaaS y Cloud Run) y SonarQube efímero.

```bash
cd backend && go test ./...
cd ../frontend && pnpm run build
cd ../scripts/IaC && terraform init -backend=false && terraform validate && terraform test
cd cloudrun && terraform init -backend=false && terraform validate && terraform test
```

## Despliegue

Seguir [docs/entrega4/despliegue.md](docs/entrega4/despliegue.md): publicar imágenes en Artifact Registry, aplicar el root `scripts/IaC/cloudrun` en `proyecto-2-cloud-509714`, ejecutar el Job de administrador y capturar evidencias. No aplicar planes viejos ni ejecutar `destroy` sin autorización.

Video de sustentación: <https://youtu.be/vMCBK4uZPUE>.

Histórico: [entrega 3](docs/entrega3/arquitectura.md), [entrega 2](docs/entrega2/arquitectura.md). El tag y el video se registran en [cierre.md](docs/entrega4/cierre.md).
