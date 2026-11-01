# Entrega 3 — Arquitectura elástica IaaS

Estado al 2026-10-29: configuración implementada y validación local en curso. **El despliegue elástico todavía no se ha aplicado ni medido en GCP.** Este documento distingue la configuración prevista de las evidencias cloud pendientes. No se considera cumplido el despliegue hasta completar [verificación cloud](operacion.md).

## Componentes

```mermaid
flowchart LR
  Usuario[Navegador: estudiante o profesor] --> Frontend[React SPA / nginx]
  Frontend -->|HTTPS /api| API[API Go: auth, cursos, matrícula, quiz, progreso]
  API -->|sesiones y tareas asynq| Redis[Redis compartido]
  Redis --> Worker[Workers Go / ffmpeg]
  API --> DB[(PostgreSQL administrado)]
  Worker --> DB
  API -->|URLs firmadas| GCS[(Almacenamiento de objetos)]
  Usuario -->|PUT original / GET contenido| GCS
  Worker -->|originales y HLS| GCS
  Worker --> ClamAV[ClamAV]
```

La API conserva el monolito modular. Redis aloja sesiones revocables y la cola `media`; los workers escanean y transcodifican fuera del ciclo HTTP. PostgreSQL contiene cursos, inscripciones, intentos, notas y progreso. Cloud Storage conserva originales, HLS y objetos públicos; el disco local del worker es temporal y se limpia con `defer`.

## Despliegue configurado

```mermaid
flowchart LR
  Internet((Internet))
  k6["Generador k6<br/>mooc-loadgen<br/>e2-highcpu-4<br/>fuera de los grupos"]
  LB["Balanceador global<br/>EXTERNAL_MANAGED<br/>IP 136.68.131.0<br/>dominio sslip.io<br/>certificado ACTIVE<br/>:443 HTTPS<br/>:80 redirige"]

  subgraph GCP["GCP · proyecto-2-cloud-509714 · us-central1 · zona us-central1-a"]
    subgraph NET["VPC mooc-vpc · us-central1"]
      NETINFO["Subred mooc-app-subnet<br/>10.10.1.0/24<br/>private_ip_google_access = true<br/>IP fija de cola 10.10.1.30"]
      API["MIG mooc-api-mig<br/>1–3 × e2-small<br/>Debian 12 · 30 GiB<br/>api:«image_tag» :8080<br/>autoscaler CPU 0,60<br/>min 1 · max 3<br/>cooldown 180 s<br/>autohealing TCP :8080"]
      FE["MIG mooc-frontend-mig<br/>1 × e2-small<br/>nginx :3000<br/>frontend:«image_tag»<br/>fijo, sin autoscaling<br/>health HTTP /"]
      W["MIG mooc-worker-mig<br/>1–3 × e2-small<br/>Debian 12 · 30 GiB<br/>worker:«image_tag» :9101<br/>autoscaler por backlog<br/>4 por instancia<br/>min 1 · max 3<br/>retira 1 / 600 s<br/>autohealing :9101/metrics"]
      Q["mooc-queue · e2-medium<br/>IP fija 10.10.1.30<br/>Redis :6379<br/>sesiones + cola asynq<br/>ClamAV :3310<br/>Mailpit :1025<br/>fuera de los grupos"]
      SQL[("Cloud SQL PostgreSQL 17<br/>db-f1-micro<br/>20 GiB PD_SSD · zonal<br/>IP privada 10.86.0.3<br/>max_connections 25<br/>PSA 10.86.0.0/16")]
      NAT["Cloud NAT + router<br/>salida sin IP pública<br/>AUTO_ONLY · toda la subred"]
      FW["Firewall por rol<br/>lb→api :8080<br/>lb→frontend :3000<br/>lb→worker :9101<br/>api,worker→queue :6379<br/>worker→queue :3310<br/>api→queue :1025<br/>IAP → :22"]
    end

    subgraph MANAGED["Servicios administrados"]
      GCS[("Cloud Storage<br/>originals · hls · public<br/>URL firmada al navegador")]
      MON["Cloud Monitoring<br/>custom.googleapis.com<br/>/mooc/queue/backlog<br/>cada 30 s"]
      SM["Secret Manager<br/>7 secretos por rol"]
      AR["Artifact Registry<br/>mooc-images<br/>etiquetas inmutables"]
    end
  end

  Internet -->|"HTTPS 443"| LB
  k6 -->|"k6"| LB
  LB -->|"/api · /health"| API
  LB -->|"resto"| FE
  API -->|"6379"| Q
  W -->|"6379 · 3310"| Q
  API -->|"5432"| SQL
  W -->|"5432"| SQL
  API -->|"URL firmada"| GCS
  W -->|"originales y HLS"| GCS
  Internet -.->|"PUT / GET directo"| GCS
  Q -->|"backlog 30 s"| MON
  MON -.->|"autoscaler"| W

  classDef lb fill:#ffec99,stroke:#f08c00,color:#1e1e1e
  classDef api fill:#b2f2bb,stroke:#2f9e44,color:#1e1e1e
  classDef worker fill:#d0bfff,stroke:#7048e8,color:#1e1e1e
  classDef queue fill:#ffd8a8,stroke:#e8590c,color:#1e1e1e
  classDef data fill:#99e9f2,stroke:#0b7285,color:#1e1e1e
  classDef ext fill:#f1f3f5,stroke:#868e96,color:#1e1e1e
  class LB lb
  class API api
  class W worker
  class FE ext
  class Q queue
  class SQL,GCS data
  class Internet,k6,NAT,FW,SM,MON,AR ext
```

Fuentes: [componentes.mmd](diagramas/componentes.mmd), [despliegue.mmd](diagramas/despliegue.mmd) y las versiones editables [componentes.excalidraw](diagramas/componentes.excalidraw) y [despliegue.excalidraw](diagramas/despliegue.excalidraw). El diagrama de despliegue detalla la subred (`10.10.1.0/24`, acceso privado a Google, IP fija de la cola), los dos autoscalers con señal, umbral, límites, estabilización y retiro, y los puertos de cada regla de firewall. Confirmar nombres y tamaños con outputs y `gcloud describe` tras desplegar.

## Plantillas e inicialización

Las plantillas definen SO, CPU/RAM mediante el tipo de máquina, discos, identidad y metadatos por rol. [variables.tf](../../scripts/IaC/variables.tf) es la fuente de valores predeterminados y [compute.tf](../../scripts/IaC/compute.tf) de la configuración efectiva. Los tres contenedores comparten una etiqueta inmutable de Artifact Registry, identificable por commit. **Las imágenes existentes `652591e65fc2` no contienen las nuevas pantallas de esta revisión**: publicar una versión nueva requiere autorización explícita.

`startup.sh` instala Docker, obtiene secretos de Secret Manager, espera las dependencias, descarga la imagen e inicia el rol. Las migraciones se serializan con `pg_advisory_lock`. Registrar `mooc/status` y `mooc/ready-uptime-sec`: la disponibilidad del proceso se verifica antes de instalar Ops Agent. Probar también un reinicio de cada rol para comprobar que no duplica procesos.

El frontend se sirve por nginx en 3000; API y SPA comparten origen detrás del balanceador. La SPA utiliza `Authorization: Bearer`, con token en `localStorage`; no usa cookies de sesión. Cerrar sesión revoca el token en Redis. Las cargas directas y HLS usan CORS de los buckets. `localStorage` hace relevante prevenir XSS; no se inserta HTML arbitrario de los recursos.

## Escalamiento y salud

| Parámetro | API | Workers |
|---|---|---|
| Grupo | `mooc-api-mig` | `mooc-worker-mig` |
| Límites | 1–3 VMs | 1–3 VMs |
| Señal | CPU media | `custom.googleapis.com/mooc/queue/backlog` |
| Objetivo | 0,6 | 4 trabajos por VM |
| Inicialización | 180 s configurados | 180 s configurados |
| Reducción | Estabilización predeterminada de GCP; registrar comportamiento real | A lo sumo 1 retiro por ventana de 600 s, más controles de GCP |
| Autohealing | TCP 8080 | HTTP 9101 `/metrics` |

La CPU refleja el costo de bcrypt y serialización de la API. Para workers se usa **pendientes + activos**, para no interpretar una cola sin pendientes como inactividad cuando todavía hay trabajos ejecutándose. Se publica una sola serie desde la VM de cola, cada 30 segundos, `resource.type=global`, etiqueta `queue=media`; `single_instance_assignment=4`. No se cambia ninguna señal ni el tipo de balanceador.

Al llegar a 3 VMs el grupo no crece más: la API puede acumular latencia/errores y la cola puede seguir creciendo. El máximo configurado no es una capacidad medida.

El LB verifica HTTP `/health` en 8080 cada 10 s, timeout 5 s, 2 éxitos para saludable y 3 fallos para no saludable. `/health` comprueba PostgreSQL y Redis. Autohealing TCP es deliberadamente menos estricto: una caída compartida de Redis no se resuelve recreando todas las APIs. El frontend se verifica por HTTP `/` en 3000. Los workers solo tienen autohealing, no reciben tráfico del balanceador.

El LB distribuye por utilización, `max_utilization=0.8`, sin afinidad configurada. Cada respuesta API incluye `X-Served-By`; probar dos instancias saludables y excluir una no saludable. **Excluir un destino del LB y reemplazar una VM por autohealing son eventos distintos.**

## Estado, integridad y retiro

Sesiones en Redis, datos en PostgreSQL y archivos en GCS permiten alternar réplicas. El pool presupuestado es 3 API × 5 + 3 workers × 2 + 3 reservadas = 24 de 25 conexiones. Terraform valida esa combinación. El despliegue gradual puede crear una VM adicional; medir conexiones durante actualizaciones y revisar el margen antes de actualizar a máxima capacidad.

`shutdown.sh` ejecuta `docker stop`. La API dispone de 25 s para solicitudes en curso y el LB tiene drenaje de conexiones. Asynq recibe SIGTERM y dispone de 60 s; los trabajos que no finalicen deben recuperarse por su mecanismo de reintentos. Esta capacidad **requiere evidencia real**, especialmente con ffmpeg activo. Concurrencia: 4 tareas por worker, entre 4 y 12 al escalar. Guardar logs por ID de trabajo/recurso, no solo contar instancias.

Controles a verificar: sesión entre réplicas, intento duplicado sin doble calificación, progreso consistente, archivos accesibles desde cualquier API autorizada, datos conservados al reemplazar API y trabajos reconciliados después del retiro de workers.

## Seguridad y limitaciones

VMs sin IP pública; SSH por IAP; firewall por rol; Cloud SQL por IP privada; una identidad de servicio por rol y permisos de Secret Manager/GCS limitados. IAM autoriza acceso a servicios cloud; la aplicación se autentica a PostgreSQL con usuario y contraseña de Secret Manager: son mecanismos distintos.

Persisten puntos únicos de falla: una zona, VM única de Redis/ClamAV y Cloud SQL sin HA. HLS y objetos públicos tienen lectura anónima; conocer una URL permite acceder fuera de la API. La autenticación de autoría protege edición, pero hay compromisos previos que deben tratarse en [deuda técnica](deuda-tecnica.md).

Costos y consumo: [costos.md](costos.md). Operación, reconstrucción y evidencia: [operacion.md](operacion.md). Flujos: [frontend.md](frontend.md). Comparación experimental: [informe](../../capacity-planning/pruebas_de_carga_entrega3.md).
