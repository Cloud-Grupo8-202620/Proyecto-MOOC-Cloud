# Entrega 5 — Análisis de oportunidades serverless

## 1. Qué ya es serverless (entrega 4)

| Componente | Servicio | Por qué cuenta como serverless |
|---|---|---|
| Frontend, backend, worker | Cloud Run (0–3 instancias) | Escala a cero, se paga por uso, sin administrar servidores |
| Cola de tareas | Pub/Sub (push + DLQ) | Gestionado, sin capacidad que aprovisionar |
| Archivos y HLS | Cloud Storage | Almacenamiento gestionado, URLs firmadas |
| Credenciales | Secret Manager | Gestionado, inyectado por Cloud Run |
| Administrador inicial | Cloud Run Job | Ejecución puntual, sin servidor permanente |

**No** son serverless: Cloud SQL (instancia `db-f1-micro` siempre encendida), Memorystore Redis (instancia Basic) y la VM de soporte (ClamAV + Mailpit).

## 2. Oportunidades identificadas

| # | Componente actual | Servicio propuesto | Beneficio | Limitaciones | Decisión |
|---|---|---|---|---|---|
| 1 | **Tarea `media.scan` del worker** (ClamAV) | **Cloud Run functions gen2 disparada por Pub/Sub (Eventarc)** | Código pequeño, orientado a eventos, escala a cero y por mensaje; separa el escaneo (I/O, segundos) del transcode (CPU, minutos); permisos propios y mínimos; deja de ocupar los 2 vCPU/2 GiB del worker | Eventarc administra su propia suscripción (sin DLQ por intentos); requiere Direct VPC para Cloud SQL y ClamAV; el build ocurre en Cloud Build; entrega *al menos una vez* | **IMPLEMENTADA** |
| 2 | Tarea `media.transcode` (ffmpeg) | Cloud Run Jobs o Transcoder API | Jobs: sin servidor HTTP y con reintentos propios. Transcoder API: sin ffmpeg que mantener | Funciones: necesitan binario ffmpeg y hasta 9 min de CPU alta, mal ajuste. Transcoder API cambia perfiles/costos y el formato HLS actual | Solo documentada |
| 3 | VM de soporte (ClamAV) | ClamAV en Cloud Run (servicio interno) | Elimina la VM y su punto único de falla | clamd necesita ~3 GiB para cargar firmas y arranque lento; el escaneo por TCP/INSTREAM exige conexiones persistentes | Solo documentada |
| 4 | VM de soporte (Mailpit) | Servicio de correo transaccional (SendGrid/Mailgun) | Sin servidor; entrega real | Cuenta externa y costo; Mailpit existe para demostrar el correo de verificación | Solo documentada |
| 5 | Frontend (nginx en Cloud Run) | Cloud Storage + Cloud CDN / Firebase Hosting | Costo casi nulo y latencia menor para estáticos | Se pierde el proxy `/api` y `/mailpit/` del mismo origen; habría que añadir CORS | Solo documentada |
| 6 | Job `provision-admin` | Ya es serverless; podría ser una función HTTP | — | Sin ventaja: ejecución única | Descartada |
| 7 | Generación de insignias / miniaturas | Cloud Function sobre eventos de Cloud Storage | Desacopla del backend, reacciona al objeto creado | Hoy es trivial (imagen estática); poco valor | Solo documentada |
| 8 | Cloud SQL | AlloyDB / Cloud SQL con *activation policy* o base serverless (Spanner/Firestore) | Pago por uso | Cambia el motor/modelo (GORM + PostgreSQL), migración costosa | Solo documentada |
| 9 | Memorystore Redis | Sesiones en Firestore o JWT sin estado | Elimina una instancia siempre encendida | Revocación de sesiones y locks TUS dependen de Redis | Solo documentada |

## 3. Por qué `media.scan` es la tarea migrada

Se evaluaron las dos tareas del worker (`media.scan` y `media.transcode`):

- **Encaja con una función**: corta, sin binarios nativos (ClamAV se consulta por TCP con la stdlib, ver `backend/scanner/clamav.go`), sin CPU sostenida. Usa justo lo que pide el enunciado: **Cloud SQL** (lee el recurso y escribe `scan_status`) y **Cloud Storage** (descarga el original y lo borra si está infectado).
- **Ya era idempotente** por estado de base de datos (`scan_status` = `pending/clean/infected`), así que migrar no exige rediseñar la consistencia.
- **Menor riesgo**: si falla, el contenido queda `pending` y no se publica (fail-closed), igual que antes.
- **Mejor aislamiento**: el worker ya no necesita acceso de red a ClamAV ni permiso de publicar en Pub/Sub; la función recibe solo el acceso que usa.
- `media.transcode` se queda en Cloud Run: ffmpeg, 2 vCPU y hasta 9 minutos son el perfil de un contenedor, no de una función.

## 4. Comportamiento conservado

| Aspecto | Antes (worker) | Ahora (función) |
|---|---|---|
| Entrada | Mensaje `media.scan` por push | Mensaje `media.scan` por Eventarc |
| Resultado limpio | `scan_status=clean` y, si es video/audio, publica `media.transcode` | Igual |
| Resultado infectado | Borra el original, `scan_status=infected`, `processing_status=failed` | Igual |
| Fail-closed | ClamAV caído → error → reintento | Igual |
| Recurso inexistente / payload inválido | Error permanente, se confirma | Igual |
| Agotar reintentos | `failed` tras 5 intentos y DLQ | `failed` tras `scan_fn_max_event_age` (1 h) y se confirma |
| Efectos duplicados | Estado del recurso | Estado del recurso (+ transcode idempotente) |

### Reintentos sin duplicar efectos

1. Una reentrega de un archivo **ya limpio** no descarga ni escanea de nuevo: solo vuelve a publicar el `transcode` con la **misma clave de idempotencia**, y `HandleTranscode` descarta el segundo mensaje si el recurso ya está `ready` (o devuelve error transitorio si otro está procesando).
2. Una reentrega de un archivo **infectado** no hace nada.
3. Un fallo **transitorio** (ClamAV, Cloud SQL, Storage) devuelve error → Eventarc reintenta con backoff; el estado solo cambia después de que ClamAV responde.
4. Un fallo **permanente** se confirma para no entrar en bucle.
5. Pasada la ventana `SCAN_MAX_EVENT_AGE`, el recurso queda `failed` y el mensaje se confirma. Es el equivalente a la DLQ, porque Eventarc no permite configurar `max_delivery_attempts` en su suscripción.

Pruebas: `backend/scanner/service_test.go` (cada caso anterior contra PostgreSQL) y `backend/functions/scanfn/function_test.go`.
