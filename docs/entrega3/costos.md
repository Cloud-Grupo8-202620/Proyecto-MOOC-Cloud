# Costos — Entrega 3

Estimación a precios de lista USD en us-central1, consultados el 2026-10-29. Mes de referencia de 730 horas; día de 24 horas. Sin descuentos, créditos, impuestos ni loadgen. **No es gasto observado ni una cotización completa.** Los importes variables se suman aparte.

## Base fija: mínimo y máximo configurados

| Componente | Cantidad mínima / máxima | Tarifa | USD/h mínimo | USD/h máximo |
|---|---:|---:|---:|---:|
| API + workers e2-small | 2 / 6 | 0,016752855 por VM-h | 0,033506 | 0,100517 |
| Frontend e2-small | 1 / 1 | 0,016752855 por VM-h | 0,016753 | 0,016753 |
| Cola/ClamAV e2-medium | 1 / 1 | 0,033505710 por VM-h | 0,033506 | 0,033506 |
| Discos VM pd-balanced 30 GiB | 120 / 240 GiB | 0,000136986 por GiB-h | 0,016438 | 0,032877 |
| Cloud SQL db-f1-micro zonal | 1 / 1 | 0,0105 por h | 0,010500 | 0,010500 |
| Cloud SQL SSD 20 GiB | 20 / 20 GiB | 0,000232877 por GiB-h | 0,004658 | 0,004658 |
| LB global, primeras 5 reglas (usa 2) | 1 tramo | 0,025 por h | 0,025000 | 0,025000 |
| Cloud NAT, VM asignadas | 4 / 8 | 0,0014 por VM-h | 0,005600 | 0,011200 |
| IP externa de NAT | 1 / 1 | 0,005 por h | 0,005000 | 0,005000 |
| **Subtotal fijo/h** | | | **0,150960** | **0,240010** |
| **Subtotal fijo/día** | | | **3,62** | **5,76** |
| **Subtotal fijo/730 h** | | | **110,20** | **175,21** |

Fuentes: [VM E2](https://cloud.google.com/products/compute/pricing/general-purpose?hl=en), [Persistent Disk](https://cloud.google.com/compute/disks-image-pricing), [Cloud SQL](https://cloud.google.com/sql/pricing?hl=en), [Load Balancing](https://cloud.google.com/load-balancing/pricing), [Cloud NAT](https://cloud.google.com/nat/pricing). Revalidar región y configuración antes de desplegar. Se supone una IP NAT y que las cuatro/ocho VM tienen asignación NAT; corroborar la asignación real. Los reemplazos durante rolling update pueden añadir instancias transitorias sobre el máximo estable de los MIG.

Fórmula reproducible para n API y n workers:

`USD/h = (2n+1)×0,016752855 + 0,033505710 + (2n+2)×30×0,000136986 + 0,0105 + 20×0,000232877 + 0,025 + (2n+2)×0,0014 + 0,005`.

El costo real de una corrida elástica se integra por tiempo en cada tamaño; no se multiplica toda la corrida por el máximo si solo se alcanzó durante parte de ella.

## Costo por configuración y marginal

Aplicando la fórmula con las tarifas de la tabla anterior:

| Configuración | USD/h | USD/día | USD/mes (730 h) |
|---|---:|---:|---:|
| 1 API + 1 worker (mínimo) | 0,15096 | 3,62 | 110,20 |
| 3 API + 1 worker | 0,19548 | 4,69 | 142,70 |
| 1 API + 3 workers | 0,19548 | 4,69 | 142,70 |
| 3 API + 3 workers (máximo) | 0,24001 | 5,76 | 175,21 |

Cada instancia adicional —API o worker— cuesta **0,022262 USD/h**, es decir 0,53 USD/día o 16,25 USD/mes
(e2-small + disco de 30 GiB + una VM más en NAT). Pasar de una a tres instancias en ambas capas sube el
costo mensual un 59%; la mayor parte del piso (balanceador, Cloud SQL y la VM de cola) no depende del
autoscaling.

## Costo de las corridas

| Corrida | Duración | Costo mínimo | Costo al máximo |
|---|---:|---:|---:|
| 3A, ciclo de API | 34 min | 0,09 USD | 0,14 USD |
| 3B, ciclo de workers | 40 min | 0,10 USD | 0,16 USD |
| Escenarios 1 y 2 completos | ~3 h | 0,45 USD | 0,72 USD |
| Día completo de pruebas al máximo | 8 h | — | 1,92 USD |

La diferencia entre el mínimo y el máximo en una corrida típica es de centavos: el experimento no es la
partida cara. Lo es el tiempo encendido. Tres semanas de laboratorio al mínimo (504 h) cuestan **≈76 USD**;
añadir ocho horas de pruebas al máximo suma **0,71 USD**.

## Consumo variable cuantificado (referencia)

Cifras de partida para completar la tabla de gasto observado; las de almacenamiento y tráfico dependen del
corpus que use la corrida.

| Concepto | Dato o supuesto | Costo |
|---|---|---:|
| Artifact Registry | 0,547 GiB en 47 versiones (medido el 2026-11-01) | ~0,005 USD/mes (0,5 GiB gratis) |
| Cloud Storage, corpus | 0,5–2 GiB de originales y HLS | 0,01–0,04 USD/mes |
| Egreso de GCS a Internet | 0,12 USD/GiB | 50 GiB de HLS ≈ 6,00 USD |
| Datos por el balanceador | 0,008 USD/GiB procesado | 50 GiB ≈ 0,40 USD |
| Datos por NAT | 0,045 USD/GiB; el acceso a GCS va por red privada (`private_ip_google_access = true`) | arranques de VM ≈ 0,10–0,20 USD por tanda |
| Monitoring y Logging | 3 series propias + métricas de host | dentro de la franquicia mensual |

No presentar esta tabla como gasto observado: el consumo real se toma de Cloud Billing con la ventana UTC
de cada corrida. Lo que falta para cerrar el criterio es esa exportación, no una nueva estimación.

## Consumo variable y otros conceptos

| Concepto | Qué medir / contabilizar |
|---|---|
| Tráfico LB | GiB procesados de entrada/salida; tarifa regional aplicable (referencia us-central1: 0,008 USD/GiB) |
| NAT | GiB procesados, referencia 0,045 USD/GiB; adicional al cargo fijo |
| GCS | GiB-mes de originales, HLS y contenido público; clases de operaciones y egreso por destino |
| Artifact Registry | GiB-mes de todas las imágenes y etiquetas conservadas, no solo la activa |
| Cloud SQL | Backups usados, crecimiento automático de disco, red y operaciones adicionales aplicables |
| Monitoring/Logging | Volumen/muestras facturables, ingestión y retención; validar franquicias vigentes de la cuenta |
| Secret Manager | Versiones activas y accesos; validar franquicias compartidas de la cuenta |
| Generador de carga | Si se autoriza: tipo, horas, disco y posible tráfico/NAT adicionales |
| IPs y recursos residuales | Dirección reservada sin uso, discos o snapshots persistentes, otros recursos del proyecto |

Referencias para completar según consumo: [Storage](https://cloud.google.com/storage/pricing), [Artifact Registry](https://cloud.google.com/artifact-registry/pricing), [Observability](https://cloud.google.com/stackdriver/pricing), [Secret Manager](https://cloud.google.com/secret-manager/pricing), [red/IP](https://cloud.google.com/vpc/network-pricing).

## Gasto real de laboratorio — pendiente

Exportar Cloud Billing filtrado por proyecto y ventana UTC de las corridas, con servicio/SKU, costo bruto, descuentos/créditos y neto. Esperar la latencia del reporte. Guardar el CSV/captura sin información de pago ni datos personales y explicar qué parte pertenece a preparación, pruebas e inactividad.

| Ventana UTC | Corridas | Horas por tamaño | Estimado fijo | Gasto bruto observado | Créditos/neto | Diferencia explicada |
|---|---|---|---|---|---|---|
| Pendiente | Pendiente | Pendiente | Pendiente | Pendiente | Pendiente | Pendiente |

Conservar evidencia del inventario final. El autoscaling tiene mínimo 1 y no representa un apagado. Cloud SQL, LB, NAT y discos pueden seguir generando cargos mientras existan. Ninguna operación de retiro se ejecuta automáticamente: requiere la instrucción explícita del usuario.
