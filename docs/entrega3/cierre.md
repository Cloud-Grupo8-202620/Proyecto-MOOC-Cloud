# Cierre de la entrega 3

Corte: 2026-11-01. La implementación y preparación local no equivalen a una entrega cloud verificada. Completar las celdas pendientes con enlaces a evidencia real.

| Requisito | Evidencia |
|---|---|
| MIG independientes, 1–3, cola fuera | Desplegado en `proyecto-2-cloud-509714`; tres MIG y cola en VM aparte ([arquitectura](arquitectura.md)) y ciclos observados en el [informe de capacidad](../../capacity-planning/pruebas_de_carga_entrega3.md) |
| Balanceador HTTPS | <https://136.68.131.0.sslip.io>, certificado administrado **ACTIVE** y `/health` 200 ([verificación](evidencia/2026-11-02/README.md)) |
| Arranque autónomo y salud | Tiempos medidos en el informe (API 59–72 s, worker 56–123 s) y retiro de API con reparación del MIG ([integridad](evidencia/2026-11-02/integridad/retiro-api.txt)) |
| Flujos profesor y estudiante | Recorrido académico completo ([e2e](evidencia/2026-11-02/frontend/e2e.log), capturas en la misma carpeta); medios bloqueados por DT-03 |
| Sesiones, consistencia y concurrencia | 30/30 lecturas con el mismo token y reparto 11/11/8 entre réplicas; doble envío con una sola nota ([api.json](evidencia/2026-11-02/integridad/api.json)) |
| Independencia del escalado | 3A y 3B con creación y retorno al mínimo ([informe](../../capacity-planning/pruebas_de_carga_entrega3.md)), figuras `e3-03` y `e3-04` |
| Sin pérdida ni efectos duplicados | Retiro manual de un worker con cuatro transcodificaciones y reconciliación 65/63/2 ([informe](../../capacity-planning/pruebas_de_carga_entrega3.md)) |
| Repetir escenarios 1 y 2 | Tabla comparativa E2/E3 en el [informe](../../capacity-planning/pruebas_de_carga_entrega3.md) |
| Métricas y gráficas | Figuras `e3-01` a `e3-05` en `capacity-planning/graficas/` y resultados en `capacity-planning/results/entrega3/` |
| Calidad | [Run 41341119569](https://github.com/Cloud-Grupo8-202620/Proyecto-MOOC-Cloud/actions/runs/41341119569) sobre `84657d6`, 0 hallazgos, reporte en [evidencia](evidencia/calidad-84657d6/README.md) |
| Arquitectura y costos | [costos.md](costos.md#consumo-observado-calculado) con estimación y consumo observado (≈1,95 USD en 7,12 h) |
| Sustentación y entrega | **Pendiente**: video y tag/release `entrega-3` |

## Identificadores finales

- Commit y tag/release: **pendiente**. Código evaluado: `84657d63c11e488f68fb736d9278d73963256879`; el tag `entrega-3` se crea sobre el commit de entrega.
- Run GitHub Actions y reporte Sonar completo: [41341119569](https://github.com/Cloud-Grupo8-202620/Proyecto-MOOC-Cloud/actions/runs/41341119569), artefacto `quality-84657d63c11e488f68fb736d9278d73963256879`, copia en [evidencia/calidad-84657d6](evidencia/calidad-84657d6/README.md).
- `image_tag` realmente desplegado: `b4d5568`; el commit evaluado por Sonar (`84657d6`) solo añade el `Dockerfile` y las pruebas, sin cambios de comportamiento.
- Proyecto: `proyecto-2-cloud-509714`.
- `app_url`, `lb_ip`, certificado: <https://136.68.131.0.sslip.io>, `136.68.131.0`, administrado **ACTIVE**.
- Directorio/archivo de evidencia de carga y de integridad: **pendiente**.
- Video de entrega 3: **pendiente**; el enlace de entrega 2 no lo sustituye.
- Evidencia funcional e integridad: [evidencia/2026-11-02](evidencia/2026-11-02/README.md).
- Informe de capacidad: [pruebas_de_carga_entrega3.md](../../capacity-planning/pruebas_de_carga_entrega3.md).
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
