# Objetivos de recuperación declarados (RTO y RPO)

**Declarados y aprobados el 17/10/2026, antes de ejecutar las pruebas
oficiales de recuperación.** Este archivo entra al historial de Git antes que
cualquier medición; la fecha del commit lo respalda. Los objetivos no se
modifican después de medir: si lo medido los incumple, la diferencia se
analiza en el informe de DR.

| Objetivo | Valor declarado |
|---|---|
| **RTO** (tiempo máximo de recuperación) | **15 minutos** |
| **RPO** (pérdida máxima de datos) | **1 hora** |

## RTO: 15 minutos

**Qué se mide:** desde que se ejecuta `P9/bootstrap.ps1` sobre un clúster
destruido hasta que el gateway responde `GET /api/salud` con HTTP 200 (los 4
microservicios arriba) **y** los datos de producción están restaurados desde
el último respaldo de Velero.

**Por qué 15 minutos:**
- El ensayo del 16/10/2026 (sin base de datos ni microservicios) tardó 5 min
  07 s (`P9/evidencias/bloque-4-ensayo-reconstruccion.txt`).
- La reconstrucción completa agrega Kyverno y sus políticas, el operador de
  PostgreSQL y un clúster de 2 instancias, 5 microservicios, la restauración
  de Velero y la descarga de imágenes. Estimación: 8 a 12 minutos.
- El margen hasta 15 minutos cubre la variación en la descarga de imágenes y
  en el arranque de contenedores en una laptop.
- Para el negocio (un café), 15 minutos sin sistema es tolerable: los
  pedidos se pueden tomar en papel y registrar después.

## RPO: 1 hora

**Qué se mide:** el tiempo entre el último respaldo completado y el momento
de la pérdida de datos. Los datos escritos en ese intervalo no se recuperan.

**Cómo se sostiene:**
- Schedule de Velero `respaldo-horario-aroma` (`0 * * * *`, retención 48 h),
  que respalda `aroma-prod` con sus volúmenes. En el peor caso se pierde
  menos de 1 hora de escrituras.
- Antes de copiar los archivos, cada instancia de PostgreSQL genera un
  volcado lógico consistente (`pg_dumpall`) dentro del mismo volumen (hook de
  Velero en `aroma-gitops/bd/postgresql.yaml`).
- Respaldos complementarios: `respaldo-diario-aroma` (15 días) y
  `respaldo-llaves` (llave de Sealed Secrets, 1 año).

**Por qué 1 hora:** perder como máximo una hora de pedidos y reseñas es
recuperable para un café, porque se pueden reconstruir con los tickets del
turno. Un día completo (el respaldo diario por sí solo) no lo sería. Un RPO
menor (minutos) exigiría replicación continua fuera del clúster (archivado
de WAL), que este entorno local no tiene.

## Orden de las pruebas oficiales

1. Pérdida de nodo: drenaje de un worker con peticiones continuas al gateway.
2. Reconstrucción completa cronometrada → **RTO medido**.
3. Eliminación y restauración de datos → **RPO medido**. Va al final para que
   el objeto Restore siga existiendo al momento de calificar.
