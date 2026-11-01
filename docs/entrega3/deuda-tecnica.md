# Deuda técnica y calidad — Entrega 3

## Línea base de la primera medición

La medición que integra la línea base es el artefacto `quality-c01365c687ceadd0f9a4abf91f1f75e913745d3e`
de la ejecución [41339407527](https://github.com/Cloud-Grupo8-202620/Proyecto-MOOC-Cloud/actions/runs/41339407527),
generado por el job `quality` sobre el commit `c01365c687ceadd0f9a4abf91f1f75e913745d3e` con
`dirty=false`. La copia íntegra vive en [evidencia/calidad-c01365c](evidencia/calidad-c01365c/README.md).

| Indicador | Valor | Unidad / interpretación |
|---|---:|---|
| Líneas analizadas | 10.959 | API, workers, frontend y Dockerfiles |
| Duplicación | 0,5 | % de líneas; umbral ≤ 20% |
| Mantenibilidad | A | `sqale_rating=1.0`; umbral A/B/C |
| Deuda técnica Sonar | 0 | minutos; equivale a 0 h y 0 días de remediación estimada |
| Bugs / vulnerabilidades / code smells | 0 / 0 / 0 | reportados por la herramienta |
| Hallazgos abiertos | 0 | `issues.json` del commit evaluado |
| Security hotspots | 0 | `hotspots.json`; no hay revisión pendiente |
| Cobertura | 5,7 | % de líneas cubiertas; informativa, no es umbral de la entrega |

El valor de deuda de Sonar no representa todo el trabajo pendiente del proyecto: los compromisos de
arquitectura, operación y seguridad de la tabla siguiente no aparecen como code smells y sí son deuda.
La herramienta mide el código de aplicación completo, sin exclusiones de código ni de frontend.

Diagnóstico previo (histórico, no es la línea base): análisis local del 2026-10-29 sobre cambios sin
commit encima de `652591e`, 9.655 líneas, duplicación 0,5%, mantenibilidad A, deuda 0 minutos y cobertura
5,7%. Su manifiesto quedó en `evidencia/local/sonar/` con `pipeline: local` y `dirty=true`; la ejecución
en Actions lo reemplaza como evidencia.

El inventario inicial tuvo 3 hallazgos (1 Major y 2 Minor). Se corrigieron en código: rechazo de promesa sin capturar en Mis cursos y ejecución como root por defecto en imágenes de API/worker. **La segunda medición local** analizó 10.952 líneas: duplicación 0,5%, mantenibilidad A, deuda 0 minutos y cobertura 5,5%; 0 bugs/vulnerabilidades/code smells abiertos y 0 hotspots. Los tres hallazgos iniciales aparecen CLOSED. [Reporte local](evidencia/local/sonar/manifest.json) (diagnóstico, `dirty=true`); la evidencia definitiva es el artefacto del commit `c01365c` descrito arriba.

| ID | Hallazgo inicial | Ubicación | Severidad Sonar | Acción | Estado |
|---|---|---|---|---|---|
| S-01 | `typescript:S9383` | `frontend/src/pages/mis-cursos.tsx` | Major | Capturar error y comunicarlo; evitar modificar el array original al ordenar | Resuelto |
| S-02 | `docker:S6471` | `backend/Dockerfile` | Minor | Usuario sin privilegios en etapa de ejecución | Resuelto |
| S-03 | `docker:S6471` | `backend/worker/Dockerfile` | Minor | Usuario sin privilegios; temporales bajo /tmp | Resuelto |
| S-04 a S-06 | `typescript:S9383` (3) | `pages/ensenar.tsx`, `pages/ingresar.tsx`, `components/app-shell.tsx` | Major | Esperar `navigate` dentro de las funciones asíncronas; corregido en `bf418d5` | Resuelto |

**Inventario Major+ abierto del commit `c01365c`: ninguno.** `issues.json` del artefacto tiene 0 entradas
y `hotspots.json` también; no hay reglas con severidad Major o superior que aplazar. La tabla anterior se
conserva como registro de los hallazgos corregidos durante el ejercicio, no como pendientes. Si se cambia
código después de este commit, la revisión debe repetirse antes de cerrar la entrega.

## Hallazgos de la primera ejecución en GitHub

La ejecución del commit `492999f` pasó los umbrales totales y exportó el reporte con `dirty=false`, pero detectó tres Major adicionales de `typescript:S9383`: navegación sin esperar en `pages/ensenar.tsx`, `pages/ingresar.tsx` y `components/app-shell.tsx`. Se corrigieron esperando `navigate` dentro de las funciones asíncronas existentes en `bf418d5` (PR #2). El reporte del commit `c01365c` ya no los lista: `issues.json` del artefacto final está vacío.

## Compromisos técnicos identificados fuera de Sonar

Estos nueve puntos no aparecen como code smells y sí son deuda: riesgos, decisiones de arquitectura y
límites del entorno de laboratorio. Responsable de seguimiento propuesto: Wyo Hann Chu; la distribución
se acuerda con Diego en la revisión de cierre. Plazos: «antes de la sustentación» para las de prioridad
alta y «entrega 4» para las medias. Los cambios de arquitectura requieren aprobación del usuario.

Cada fila sigue los campos exigidos: identificador y categoría, descripción con ubicación, evidencia,
impacto, prioridad, tratamiento con criterio de verificación, responsable y plazo, y estado.

| ID · categoría | Elemento y ubicación · evidencia | Impacto | Prioridad | Tratamiento y criterio de verificación | Responsable · plazo · estado |
|---|---|---|---|---|---|
| DT-01 · Arquitectura / disponibilidad | Cola (Redis + ClamAV) y Cloud SQL en una sola zona e instancia, `compute.tf` (`google_compute_instance.queue`) y `sql.tf`. Evidencia: un solo recurso de cada tipo; sin réplica ni failover. | Una falla compartida afecta a los dos grupos; escalar workers no repara Redis. | Alta | Mantener el alcance de laboratorio documentado y medir la recuperación; proponer HA solo con costo y aprobación. Cierre: documento de escenario de falla con tiempo de recuperación observado. | Wyo Hann Chu · antes de la sustentación · Pendiente (limitación declarada) |
| DT-02 · Seguridad | HLS y objetos públicos servidos por URL de GCS; el control práctico es la URL, no la autorización de la API. Evidencia: bucket con lectura anónima en `storage.tf`; segmentos accesibles sin sesión. | Una URL compartida permite consumo fuera de la autorización de inscripción. | Alta | Evaluar entrega firmada de manifiestos y segmentos con prueba de acceso por usuario no inscrito. Cierre: prueba negativa que devuelve 403 sin inscripción. | Wyo Hann Chu · antes de la sustentación · Pendiente |
| DT-03 · Confiabilidad / procesamiento | La carga se autoriza antes de completar el PUT; `uploads/` + `worker/handlers_media.go`. Evidencia: el backoff de reintentos es lo que evita la carrera. | El worker puede intentar leer un objeto todavía ausente; el tiempo hasta `available` crece. | Alta | Medir `time-to-available` y diseñar confirmación de carga/outbox con reintento que verifique el objeto. Cierre: carga que llega antes del objeto termina `available` sin reintentos manuales. | Wyo Hann Chu · antes de la sustentación · Pendiente |
| DT-04 · Código / idempotencia | Reemplazo de archivo: TaskID estable y actualizaciones por recurso (`queue/queueclient.go`, `worker`). Evidencia: dos cargas del mismo recurso comparten clave. | Una segunda carga puede interferir con la tarea de la primera y dejar derivados mezclados. | Alta | Identidad por generación, rechazo de claves ajenas y actualizaciones condicionales; prueba de dos cargas concurrentes más un retry. Cierre: ambos derivados conservan su objeto de origen. | Wyo Hann Chu · antes de habilitar reemplazos como flujo soportado · Pendiente |
| DT-05 · Código / autorización | Vista pública del árbol del curso publicado (`courses/coursecontroller.go` `GetDetail`, `courseservice.go` `GetFullTree`): la versión publicada se sirve sin autenticación y `GetFullTree` prefiere el `draft` cuando existe. Evidencia: lectura de ambas funciones. | El estudiante ve el contenido de un borrador posterior y campos de autoría que no corresponden a la versión vigente. | Alta | Separar catálogo de contenido autorizado y seleccionar la versión vigente para estudiantes; pruebas de anónimo y no inscrito. Cierre: respuesta pública sin campos de autoría y con la versión publicada. | Wyo Hann Chu · antes de la sustentación · Pendiente |
| DT-06 · Operación / capacidad | Presupuesto de conexiones 24/25 (`variables.tf`, `db_max_connections=25`). Evidencia: cálculo del pool en `arquitectura.md`. | Durante un rolling update la instancia temporal puede agotar Cloud SQL y provocar errores en ambos grupos. | Alta | Medir conexiones de la instancia temporal antes de actualizar con ambos MIG al máximo; ampliar el tier o bajar el pool si no hay margen. Cierre: rolling update con error rate 0 y conexiones medidas. | Wyo Hann Chu · antes de la sustentación · Pendiente |
| DT-07 · Pruebas | Cobertura automática 5,7% (artefacto `c01365c`). Evidencia: `measures.json`. | Ramas de error y concurrencia pueden fallar aunque build y escáner estén verdes. | Media | Priorizar integración de autorización, reintentos, doble entrega y progreso; conservar la cobertura real sin excluir código. Cierre: cobertura de esas rutas medida en CI. | Equipo · entrega 4 · Pendiente |
| DT-08 · Seguridad / sesión | Token en `localStorage` (`frontend/src/lib/api.ts`, `auth.tsx`). Evidencia: sesión revocable en Redis, sin cookie `HttpOnly`. | Un XSS podría robar la sesión; el token viaja en cada petición del SPA. | Media | Mantener renderizado de texto seguro, revisar enlaces y dependencias, evaluar cookie `HttpOnly` con CSRF. Cierre: decisión documentada con prueba de expiración y revocación. | Equipo · entrega 4 · Pendiente |
| DT-09 · Rendimiento / frontend | Peso del bundle con HLS y componentes de UI. Evidencia: advertencia de chunk >500 kB en el build de Vite. | Mayor descarga inicial en redes lentas. | Media | HLS ya se carga de forma diferida en la ruta de consumo; medir y dividir por uso real. Cierre: chunk principal bajo el umbral con la misma funcionalidad. | Equipo · entrega 4 · Pendiente |

## Correcciones funcionales de esta revisión

Propiedad del autor en edición/carga/validación; quiz publicable con preguntas reales; lookup autorizado del quiz y sus intentos; respuesta no marcada no cuenta como opción cero correcta; clave idempotente de intento consultada con identidad de estudiante; bloqueo de archivos no escaneados/disponibles; registro público sin asignación de rol admin; aprovisionamiento administrativo por stdin del operador.

Estas correcciones entraron en `8bf3757` y se endurecieron en `bf418d5` (PR #2); el reporte final del
commit `c01365c` no deja hallazgos abiertos sobre ellas.

La matriz no es un análisis de seguridad exhaustivo. Antes de cerrar, contrastar estos compromisos con los resultados de carga y agregar defectos observados con evidencia y fecha. No usar una calificación A para declarar que no existen riesgos arquitectónicos.

## Acta final

| Campo | Valor |
|---|---|
| SHA de código evaluado | `c01365c687ceadd0f9a4abf91f1f75e913745d3e` |
| Tag / release | `entrega-3` — pendiente de crear sobre el commit de entrega; no cambia el código evaluado |
| URL pipeline | <https://github.com/Cloud-Grupo8-202620/Proyecto-MOOC-Cloud/actions/runs/41339407527> |
| Reporte completo, servidor/scanner y perfiles | [evidencia/calidad-c01365c](evidencia/calidad-c01365c/README.md); SonarQube Community 26.10.0.133078; perfiles en `profiles.json`; `dirty=false` |
| Duplicación total (≤20%) | 0,5% |
| Mantenibilidad (A/B/C) | A |
| Deuda Sonar, minutos y conversión a horas/días | 0 minutos = 0 h = 0 días |
| Major / Critical / Blocker abiertos, responsables y plazos | 0 / 0 / 0; no hay hallazgos que aplazar |
| Revisión de hotspots | 0 hotspots en el commit evaluado |

Nota de trazabilidad: el artefacto corresponde al commit `c01365c`, que ya incluye el `frontend/Dockerfile`
corregido y las pruebas de navegador ampliadas; los commits posteriores son solo documentación. Si cambia
código de aplicación antes de cerrar, repetir el job `quality` y actualizar esta acta con el artefacto del
nuevo SHA.

Procedimiento reproducible: [calidad.md](calidad.md).
