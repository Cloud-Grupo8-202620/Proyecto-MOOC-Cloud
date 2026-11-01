# Calidad y reproducción de SonarQube

No hay un proyecto SonarCloud/SonarQube conectado al repositorio. La configuración queda lista para GitHub Actions sin contratar servicios ni guardar tokens: el job `quality` levanta SonarQube Community dentro del runner, cambia la contraseña inicial, genera una credencial efímera, analiza y exporta el resultado antes de retirar el servidor. No aprovisiona GCP. El historial persistente son los artefactos de Actions, no la base de datos efímera.

## Reporte del commit evaluado

| Campo | Valor |
|---|---|
| Ejecución | [run 41341119569](https://github.com/Cloud-Grupo8-202620/Proyecto-MOOC-Cloud/actions/runs/41341119569) |
| Commit | `84657d63c11e488f68fb736d9278d73963256879` (`dirty=false`) |
| Artefacto | `quality-84657d63c11e488f68fb736d9278d73963256879` |
| Copia en el repositorio | [evidencia/calidad-84657d6](evidencia/calidad-84657d6/README.md) |
| Fecha UTC | 2026-11-01T19:22:08Z |
| Servidor | SonarQube Community 26.10.0.133078 |

| Indicador | Medido | Umbral |
|---|---:|---|
| Líneas de código analizadas | 10.959 (`go=5588; ts=5166; css=171; docker=34`) | — |
| Duplicación | 0,5% | ≤ 20% |
| Mantenibilidad | A (`sqale_rating=1.0`) | A, B o C |
| Deuda técnica estimada | 0 minutos | registrar e interpretar |
| Bugs / vulnerabilidades / code smells | 0 / 0 / 0 | — |
| Hallazgos abiertos (`issues.json`) | 0 | Major+ con motivo de aplazamiento |
| Security hotspots | 0 | revisión humana |
| Cobertura | 5,7% | informativa |

`dirty=false` confirma que el análisis corresponde al commit publicado y no a un árbol con cambios. La
copia local previa en `evidencia/local/sonar/` (`pipeline: local`, `dirty=true`) queda como diagnóstico
intermedio: no se usa como evidencia final. Este análisis incluye el `frontend/Dockerfile` corregido y las
pruebas de navegador ampliadas del commit `84657d6`; los commits posteriores son solo documentación. Si se
modifica código de aplicación, repetir el job `quality` sobre el commit final antes de cerrar. El gate exportado no trae condiciones (`gate.json`): el cumplimiento de los umbrales de la
entrega lo verifica `scripts/quality/sonar.py` sobre las métricas totales, no el gate estándar.

## Ejecutar y conservar

1. Subir el commit a la rama del PR y abrir **Actions → Verificación entrega 3**. Se ejecuta con push, pull request o Run workflow.
2. Verificar `backend`, `frontend`, `browser`, `terraform` y `quality`. Las pruebas Terraform usan mocks: no crean infraestructura.
3. Descargar `quality-<SHA>` y comprobar `manifest.json`: commit exacto, `dirty=false`, URL de ejecución y analysis ID. Para el cierre ejecutar sobre el commit definitivo; un diagnóstico local con cambios sin commit no es evidencia final.
4. Conservar el ZIP completo en la entrega antes de sus 90 días de retención y enlazar el run en [cierre.md](cierre.md). No copiar `.scannerwork`, credenciales temporales, traces de navegador ni datasets de sesiones.
5. Actualizar [deuda-tecnica.md](deuda-tecnica.md) con las métricas y todos los hallazgos abiertos Major o superiores. Ningún Critical/Blocker puede quedar sin corrección o plan con responsable y fecha.

El job comprueba **métricas totales**: duplicación ≤20%, mantenibilidad A/B/C, deuda disponible y código Go/TypeScript realmente analizado. El Quality Gate estándar de Sonar se exporta por separado; no confundir su evaluación de cobertura/código nuevo con los umbrales específicos del enunciado. La cobertura es informativa, nunca se elimina código del análisis para mejorar cifras.

## Archivos auditables

| Archivo | Contenido |
|---|---|
| `manifest.json`, `task.json` | Revisión, fecha, pipeline y análisis exacto |
| `measures.json`, `summary.txt` | Líneas, lenguajes, duplicación, rating, deuda en minutos, cobertura |
| `issues.json` | Hallazgos completos paginados, reglas, severidades y ubicaciones |
| `hotspots.json` | Revisión de seguridad pendiente, separada de vulnerabilidades confirmadas |
| `profiles.json`, `gate.json` | Perfiles activos y estado del gate |
| `images.json`, `server.log` | Versiones/digests y diagnóstico del servidor |

El alcance de [sonar-project.properties](../../sonar-project.properties) incluye API, worker y todo `frontend/src`. Solo separa pruebas de fuentes. El reporte Go se genera con `go test -race -coverprofile=coverage.out ./...`, incluyendo PostgreSQL y Redis reales de CI.

## Ejecución local opcional

Requiere Docker con memoria suficiente; evitar ejecutar Sonar, ClamAV y compilaciones simultáneamente en una VM Docker pequeña. El workflow contiene la receta completa. En macOS usar red Docker compartida para conectar scanner y servidor; `--network host` del workflow está pensado para el runner Linux. Para worktrees con `.git` fuera del montaje, solo en el diagnóstico local se pueden usar `-Dsonar.scm.disabled=true -Dsonar.scm.exclusions.disabled=true`; registrar el SHA y `dirty` conserva la distinción con CI.

Una instalación persistente futura es opcional: crear proyecto, asignar URL/key y almacenar el token como secret de Actions. Reemplazar únicamente bootstrap/retirada por esa conexión, preservando el análisis y la exportación. No incluir el token en archivos versionados. Referencia: [Web API de SonarQube](https://docs.sonarsource.com/sonarqube-server/extension-guide/web-api/).
