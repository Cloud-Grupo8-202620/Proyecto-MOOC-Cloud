# Evidencias — Entrega 4

Cada corrida se guarda en una carpeta con fecha UTC:

```
docs/entrega4/evidencia/2026-11-14T120000Z/
├── despliegue.json
├── limites.json
├── iam/
│   ├── frontend.json
│   ├── backend.json
│   └── worker.json
├── pubsub/
│   ├── topic.json
│   ├── subscription.json
│   └── dlq.json
├── secretos.json
├── servicios/
│   ├── frontend.json
│   ├── backend.json
│   └── worker.json
├── logs/
│   ├── backend.json
│   └── worker.json
└── escalamiento/
    ├── instancias.json
    └── pendientes.json
```

Se genera con:

```bash
PROJECT_ID=proyecto-2-cloud-509714 ./scripts/entrega4/capturar_evidencia.sh
```

Reglas:

- No guardar valores de secretos, tokens, contraseñas ni URLs firmadas.
- No editar los JSON exportados; si hace falta un resumen, agregarlo aparte.
- Registrar fecha, commit, etiqueta de imagen y comandos ejecutados.
- La evidencia de una tarea debe incluir el `message_id` y el `resource_id`.
- Para la reentrega, conservar logs antes/después y el listado del bucket HLS.
