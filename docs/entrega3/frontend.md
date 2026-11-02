# Verificación funcional del frontend

## Alcance y estado

Implementación React integrada con la API, sin datos simulados. El entorno cloud está desplegado en `proyecto-2-cloud-509714` (<https://136.68.131.0.sslip.io>) con la imagen `b4d5568`. Estado: recorrido académico **verificado en el despliegue** ([evidencia del 2026-11-02](evidencia/2026-11-02/README.md), Playwright 19,3 s con capturas de profesor, estudiante y móvil). El recorrido con medios quedó bloqueado por la carrera entre la autorización de la carga y el PUT, documentada en esa evidencia; la verificación local no lo sustituye.

| Rol / flujo | Ruta | Evidencia |
|---|---|---|
| Ambos: entrar y salir | `/ingresar`, menú de cuenta | Login real y cierre con revocación en el [recorrido del 2026-11-02](evidencia/2026-11-02/frontend/e2e.log) |
| Profesor: sus cursos | `/ensenar` | `/ensenar` lista solo los del autor; edición ajena rechazada por API en el mismo [recorrido](evidencia/2026-11-02/frontend/e2e.log) |
| Profesor: crear y editar | `/ensenar`, `/ensenar/:id` | Curso, módulo y unidad creados y persistidos ([e2e](evidencia/2026-11-02/frontend/e2e.log)) |
| Profesor: recursos y archivos | `/ensenar/:id/recursos/:resourceId` | Creación y edición sí; la carga de archivos queda bloqueada por la carrera de DT-03, documentada en la [evidencia](evidencia/2026-11-02/README.md) |
| Profesor: quiz | Misma ruta de recurso | Quiz creado y pregunta editada, persistente tras recargar ([e2e](evidencia/2026-11-02/frontend/e2e.log)) |
| Profesor: publicación | `/ensenar/:id` | Validación y publicación desde la interfaz; el curso aparece en el catálogo ([e2e](evidencia/2026-11-02/frontend/e2e.log)) |
| Estudiante: catálogo y detalle | `/`, `/cursos/:id` | Curso publicado encontrado y abierto por el estudiante ([e2e](evidencia/2026-11-02/frontend/e2e.log)) |
| Estudiante: inscripción y cursos | `/cursos/:id`, `/mis-cursos` | Inscripción real y acceso al contenido ([e2e](evidencia/2026-11-02/frontend/e2e.log)) |
| Estudiante: consumo | `/cursos/:id/recursos/:resourceId` | Texto verificado; video, PDF, imagen y audio bloqueados por DT-03 ([evidencia](evidencia/2026-11-02/README.md)) |
| Estudiante: progreso | Recurso y `/cursos/:id` | Heartbeat y resumen del servidor ([e2e](evidencia/2026-11-02/frontend/e2e.log)) |
| Estudiante: quiz y nota | Ruta del recurso quiz | Envío, nota persistida tras recargar y un solo intento ([e2e](evidencia/2026-11-02/frontend/e2e.log)) |
| Autorización | API y rutas protegidas | Admin anónimo, escalamiento de rol y edición ajena rechazados en el mismo [recorrido](evidencia/2026-11-02/frontend/e2e.log) |

## Resultado local del 2026-11-01

Playwright Chromium: **1 recorrido completo aprobado (30,4 s)**, con escaneo ClamAV y conversión ffmpeg reales, video sintético MP4 de 30 s, reproducción HLS, heartbeat y nota persistente. El recorrido cubre ahora los cinco estados de interfaz y los tres tipos de archivo:

- estados: vacío en `/ensenar` de un profesor nuevo, error de credenciales con el mensaje del servidor, y disponibilidad tras el procesamiento;
- archivos: video, PDF, imagen y audio, cargados desde la interfaz y consumidos por el estudiante;
- evaluación: quiz con un solo intento, edición de una pregunta existente que persiste tras recargar, y botón «Intentos agotados» al gastarlo;
- autorización: creación de admin anónima rechazada, escalamiento de rol por estudiante rechazado y edición de un curso ajeno por otro profesor rechazada.

Capturas locales: [publicación](evidencia/local/profesor-publicacion.png), [resultado](evidencia/local/estudiante-resultado.png), [móvil 390 px](evidencia/local/estudiante-movil.png). No hay desbordamiento horizontal en la vista móvil comprobada.

Siguen sin cobertura automática la expiración temporal de un intento —el quiz no expone límite de tiempo en la interfaz— y la recuperación ante fallos del worker; la tabla no implica cobertura de todas las variantes. Las cargas de reemplazo quedan fuera del flujo soportado: se agrega un recurso nuevo para otro archivo, según [deuda técnica](deuda-tecnica.md). El recorrido sobre el despliegue cloud es independiente de este resultado local.

## Prueba automatizada de navegador

[connected-flow.spec.ts](../../frontend/e2e/connected-flow.spec.ts) prepara únicamente las cuentas mediante API; crea curso, módulo, unidad, lectura, video, PDF, imagen, audio y quiz desde la interfaz. Publica como profesor, cierra sesión, se inscribe como estudiante, consume los cuatro tipos de contenido, registra progreso y envía el quiz; recarga para comprobar la nota persistida. Las imágenes y el PDF son fixtures pequeños en `frontend/e2e/fixtures/`; el audio y el video se generan con ffmpeg en CI y en local deben venir de Git LFS. No usar capturas como sustituto de los resultados de esta prueba.

```bash
# Desarrollo (preserva volúmenes existentes; .env local según .env.example)
docker compose -p mooc-local -f docker-compose.yml -f compose.dev.yml up -d --build
cd frontend
pnpm install --frozen-lockfile
pnpm exec playwright install chromium
# Video y audio de Git LFS deben estar descargados (git lfs pull).
# Alternativa: E2E_VIDEO_PATH y E2E_AUDIO_PATH con medios sintéticos reales.
cd ..
python3 scripts/test_browser.py
```

Para cloud, usar `E2E_BASE_URL=https://<dominio>`, `E2E_ADMIN_USER` y `E2E_ADMIN_PASSWORD` del canal privado. El test crea cuentas y contenido de prueba: ejecutar solamente en el entorno de laboratorio. No guardar secretos ni traces con credenciales en el repositorio o en artefactos públicos. `E2E_MEDIA=false` permite diagnosticar los flujos académicos sin worker, pero **no acredita el recorrido completo**.

Guardar tras la ejecución cloud: commit e image_tag, URL, fecha UTC, salida de la prueba y capturas de publicación, procesamiento, consumo y nota. Revisar los artefactos antes de compartirlos: traces de red pueden contener tokens y URLs firmadas.

## Estados y decisiones

Controles deshabilitados durante mutaciones; mensajes de errores del servidor; carga y vacíos; consulta del procesamiento cada 5 s; archivos pendientes bloqueados en API y pantalla. El alumno recibe reglas e intentos propios del quiz sin las respuestas correctas. La UI permite editar borradores; la versión publicada conserva su inmutabilidad.

No forman parte del mínimo exigido: panel administrativo, recuperación de contraseña ni analítica avanzada. No confundir su ausencia con deuda técnica sin identificar un compromiso concreto.
