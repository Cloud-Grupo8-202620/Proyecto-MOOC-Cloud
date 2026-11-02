# Operación, evidencias y reconstrucción

## Antes de crear recursos

No ejecutar `apply`, publicación de imágenes, importación, borrado ni `destroy` sin permiso explícito del responsable en ese momento. Las lecturas y planes están permitidos. Trabajar en el directorio original `scripts/IaC`: el estado es local; no copiarlo a otro worktree.

1. Trabajar en `mooc-entrega3` (`gcloud config set project mooc-entrega3`) y consultar
   `gcloud compute instances list --filter='name~^mooc-'`.
2. Si existen recursos `mooc-*` y falta tfstate, detenerse y mostrar el inventario. No importar ni recrear por cuenta propia.
3. Comprobar identidad/proyecto, región y cuota, tfvars ignorado, imagen final y ausencia de cambios inesperados.
4. Ejecutar `terraform init`, `terraform validate` y `terraform plan -out=plan.tfplan`. Revisar el plan nuevo: el plan de 108 recursos del handoff referencia una imagen anterior.
5. Cuando se autorice publicar código: construir las tres imágenes con `scripts/publish_images.sh`, actualizar image_tag local y rehacer el plan. Cuando se autorice desplegar: aplicar ese plan concreto.

En un proyecto creado desde cero el repositorio `mooc-images` lo crea Terraform y no requiere import.
Solo si se reutiliza un proyecto con el repositorio ya existente hay que importarlo antes de aplicar:

```bash
terraform import google_artifact_registry_repository.images \
  projects/mooc-entrega3/locations/us-central1/repositories/mooc-images
```

No versionar tfvars, estado, plan, credenciales, tokens ni datasets con sesiones.

## Validación posterior

Guardar salidas con fecha UTC en `docs/entrega3/evidencia/<corrida>/`, eliminando secretos. Ejecutar desde IaC:

```bash
terraform output app_url
terraform output lb_ip
gcloud compute instance-groups managed list-instances mooc-api-mig --zone us-central1-a
gcloud compute instance-groups managed list-instances mooc-worker-mig --zone us-central1-a
gcloud compute backend-services get-health mooc-api-backend --global
gcloud compute ssl-certificates list
```

Por VM, capturar guest attributes `mooc/status` y `mooc/ready-uptime-sec`; revisar logs de arranque sin exportar secretos. En queue, revisar `journalctl -u mooc-queue-metrics`; en autoscalers, `statusDetails` y `recommendedSize`. Verificar `/health` por HTTPS y `X-Served-By`. Certificado administrado debe estar ACTIVE para el recorrido de navegador.

Registrar en `despliegue.json`: commit, image_tag, app_url, lb_ip, proyecto, zona, fecha, tipos de VM, tamaños efectivos, límites del pool, concurrencia y evidencia del certificado. Son datos observados: no rellenarlos con valores supuestos.

## Integridad y salud

- Enviar una secuencia autenticada con el mismo token a través del LB; correlacionar X-Served-By y misma identidad/datos entre al menos dos APIs.
- Crear inscripción, intento y progreso; reenviar el mismo intento y comprobar nota/efectos únicos en PostgreSQL administrado.
- Con permiso para la prueba de fallo, detener únicamente el contenedor API de una VM identificada. Observar primero exclusión del LB y luego, separadamente, eventual reparación de MIG. No hacerlo sobre la única API disponible.
- Registrar peticiones en curso y drenaje al retirar API. Verificar datos después del reemplazo.
- Con permiso para retiro, identificar un worker con tarea activa y ejecutar la acción acordada. Guardar logs antes/después por ID, destino de recuperación y objetos finales. **Esta prueba controlada no reemplaza la reducción automática del escenario 3B.**
- Conciliar todos los trabajos aceptados; fallos requieren causa diagnosticada, no descartar filas.

## Verificaciones de integridad y operación

Las seis comprobaciones del enunciado, con el comando que las produce y el archivo que se guarda en
`docs/entrega3/evidencia/<corrida>/integridad/`. Sin estas seis evidencias el componente no se acredita.

| # | Verificación | Cómo se ejecuta | Resultado esperado | Evidencia |
|---|---|---|---|---|
| 1 | Sesión continua entre réplicas | `task gcp:reparto PETICIONES=40` y el bloque de réplicas de `task integridad` | al menos 2 `X-Served-By` distintos y las 20 lecturas autentican | `reparto.txt`, `integridad-summary.json` |
| 2 | Lecturas y escrituras consistentes | crear inscripción, intento y progreso; releerlos repartidos por el LB | mismos datos en todas las réplicas | `consistencia.json` |
| 3 | Intento duplicado sin doble calificación | `task integridad` | `double_grade_total=0` y `duplicated_attempt_total=0` | `integridad-summary.json` |
| 4 | Archivos accesibles desde cualquier instancia | `download-url` y GET del objeto repetidos por el LB y directo a GCS | 200 y mismo tamaño en todas | `archivos.txt` |
| 5 | Datos conservados al retirar una API | detener el contenedor API de una VM y consultar después | datos intactos y servicio continuo por otra réplica | `retiro-api/` |
| 6 | Worker retirado con un trabajo activo | subir un video, ver `active` en la cola, detener el worker | el trabajo se reencola y termina una sola vez | `retiro-worker/` |

Comandos de apoyo:

```bash
# 1 y 4: reparto y archivos
task gcp:reparto PETICIONES=40 | tee ../docs/entrega3/evidencia/<corrida>/integridad/reparto.txt

# 2 y 3: invariantes (incluye el envío duplicado y las réplicas)
task integridad

# 5: exclusión del balanceador antes de la reparación del grupo
gcloud compute backend-services get-health mooc-api-backend --global
gcloud compute ssh <vm-api> --zone us-central1-a --tunnel-through-iap \
  --command 'docker stop $(docker ps -q --filter ancestor=us-central1-docker.pkg.dev/<proyecto>/mooc-images/api:<tag>)'
```

Registrar en `retiro-api/` y `retiro-worker/` el estado del backend (`HEALTHY`/`UNHEALTHY`), la hora de
exclusión, la de reemplazo por el MIG y los logs por ID de trabajo. El retiro de un worker durante el
procesamiento es la única prueba que no se puede sustituir por la reducción automática del grupo.

## Corridas y conservación

1. Ejecutar el recorrido de [frontend](frontend.md).
2. Escenarios 1 y 2 con la misma demanda y corpus de entrega 2; repetir corridas y conservar resultados sin sobrescribirlos.
3. Escenarios 3A y 3B independientes; registrar demanda, señal, recomendación, creación, estado operativo, consumo/balanceo y retiro.
4. Exportar Cloud Monitoring y logs; conservar versión del generador y comprobar que no está saturado.
5. Completar informe, costos y video con datos reales. El video puede usar registros de procesos largos si están completos y accesibles.

## Retiro y reconstrucción

Después de conservar evidencia y respaldos, presentar inventario y plan de retiro al responsable. `terraform destroy` requiere una orden explícita; **no se ejecuta como cleanup de pruebas, CI ni scripts de observación**. No existe un apagado gratuito que conserve todos los recursos.

Para reconstruir, conservar código/tag, imágenes identificables, configuración no sensible y procedimiento. Recuperar secretos desde el canal privado, revisar recursos existentes/estado y volver al procedimiento autorizado. La sustentación debe usar Cloud SQL, aunque se haya verificado previamente en local.
