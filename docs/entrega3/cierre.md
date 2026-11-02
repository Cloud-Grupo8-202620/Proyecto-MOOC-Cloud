# Cierre de la entrega 3

Corte: 2026-11-01. La implementación y preparación local no equivalen a una entrega cloud verificada. Completar las celdas pendientes con enlaces a evidencia real.

| Requisito | Preparación en repositorio | Evidencia final pendiente |
|---|---|---|
| MIG independientes, 1–3, cola fuera | Terraform + 17 pruebas de configuración | Plan vigente, apply autorizado, inventario RUNNING |
| Balanceador HTTPS | Rutas API/frontend, redirección y certificado | Certificado ACTIVE, backends HEALTHY, URL pública |
| Arranque autónomo y salud | startup/shutdown, guest attributes, autohealing | Reinicio/sustitución y tiempos observados |
| Flujos profesor y estudiante | UI conectada, prueba Playwright | Recorrido sobre imagen final cloud |
| Sesiones, consistencia y concurrencia | Redis, migraciones con lock, integración | Sesión entre réplicas, integridad bajo carga |
| Independencia del escalado | CPU API; backlog workers | Ciclos 3A y 3B con aumento y reducción automáticos |
| Sin pérdida ni efectos duplicados | TaskIDs, estado compartido, reconciliación | Retirada de worker ocupado y trazabilidad por tarea |
| Repetir escenarios 1 y 2 | k6/corpus e informe E2 disponibles | Corridas E3 repetidas y comparación cuantitativa |
| Métricas y gráficas | Observador MIG + exportador + gráfica | Series CPU/memoria/DB/cola/errores y tiempos |
| Calidad | Workflow Sonar efímero y exportación completa | [Run 41341119569](https://github.com/Cloud-Grupo8-202620/Proyecto-MOOC-Cloud/actions/runs/41341119569) sobre `84657d6`, 0 hallazgos, reporte en [evidencia](evidencia/calidad-84657d6/README.md) |
| Arquitectura y costos | Documentos y fuentes Mermaid | Capturas/consumo real y ajuste tras desplegar |
| Sustentación y entrega | Guion abajo, README enlazado | Video, revisión con Diego, merge y release/tag |

## Identificadores finales

- Commit y tag/release: **pendiente**. Código evaluado: `84657d63c11e488f68fb736d9278d73963256879`; el tag `entrega-3` se crea sobre el commit de entrega.
- Run GitHub Actions y reporte Sonar completo: [41341119569](https://github.com/Cloud-Grupo8-202620/Proyecto-MOOC-Cloud/actions/runs/41341119569), artefacto `quality-84657d63c11e488f68fb736d9278d73963256879`, copia en [evidencia/calidad-84657d6](evidencia/calidad-84657d6/README.md).
- `image_tag` realmente desplegado: `ad21fb9562a7` (árbol de código idéntico al commit evaluado `84657d6`; los commits posteriores solo tocan documentación).
- Proyecto: `mooc-entrega3` (número `444582133660`).
- `app_url`, `lb_ip`, certificado: <https://8.232.5.195.sslip.io>, `8.232.5.195`, administrado **ACTIVE**.
- Directorio/archivo de evidencia de carga y de integridad: **pendiente**.
- Video de entrega 3: **pendiente**; el enlace de entrega 2 no lo sustituye.
- Usuarios de prueba y credenciales: canal privado del curso.

## Guion de sustentación

1. Presentar problema y arquitectura: API y worker independientes, cola compartida, DB/GCS y frontend; explicar por qué el worker escala por backlog y la API por CPU.
2. Entrar como profesor desde el navegador. Crear curso, módulo, unidad, lectura, archivo y quiz; enseñar estados de escaneo/proceso, validación y publicación.
3. Entrar como estudiante: catálogo, inscripción, mis cursos, consumo real, progreso, evaluación y nota persistente tras recargar. Mostrar errores/permisos sin exponer credenciales.
4. Mostrar `/estado`, identidad `X-Served-By`, backends y continuidad de sesión entre réplicas. Explicar salud del LB frente a autohealing del MIG.
5. Mostrar evidencia 3A y 3B en la misma escala UTC: carga, señal, réplicas, readiness, aumento y retorno al mínimo. Explicar reacción/arranque y límites observados.
6. Mostrar reconciliación de trabajos y recuperación del worker interrumpido; diferenciar reintentar de duplicar el efecto.
7. Comparar E2/E3, costos y cuello de botella. Mostrar Actions/Sonar del SHA final, deuda y compromisos pendientes.
8. Cerrar con URL pública, repo y release/tag final. Participación de los integrantes según enunciado. Ajustar duración al formato solicitado por el curso.

## Secuencia de cierre

Primero revisar y commitear los cambios con autoría acordada. Ejecutar Actions y corregir fallos. Con permiso específico, publicar imágenes nuevas, actualizar tfvars local, comprobar recursos mooc-* existentes y state, generar un plan nuevo y revisar sus cambios. El plan anterior no contiene las imágenes nuevas. Aplicar solo tras autorización explícita; el permiso para preparar la entrega no autoriza crear infraestructura.

Luego verificar cloud, ejecutar corridas y completar informes. Incorporar evidencia al commit de entrega, volver a ejecutar calidad sobre ese SHA, coordinar revisión/merge con Diego y crear la release/tag acordada. No fabricar una release “final” con requisitos pendientes. Al terminar, solicitar la operación de retiro cuando el usuario decida; nunca ejecutar destroy como parte automática de pruebas o CI.
