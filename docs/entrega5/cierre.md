# Entrega 5 — Checklist

| Rúbrica | Entregable | Estado |
|---|---|---|
| Análisis serverless | [analisis-serverless.md](analisis-serverless.md) | Hecho |
| Migración a la función | `backend/functions/scanfn`, `backend/scanner`, worker sin `media.scan`, pruebas Go | Código listo; falta verificar en GCP |
| Terraform | `scripts/IaC/cloudrun/functions.tf` y archivos asociados; `terraform validate` y `terraform test` (18 pruebas) | Listo; falta `apply` real |
| Configuración y acceso | Variables `scan_fn_*`, cuentas dedicadas, secretos en Secret Manager, `.gitignore` de estado/tfvars/tfbackend | Hecho |
| Documentación | [despliegue.md](despliegue.md), [arquitectura.md](arquitectura.md), diagramas | Hecho |
| Evidencias y video | [evidencia/](evidencia/README.md), [video.md](video.md) | **Pendiente** (despliegue real y grabación) |
