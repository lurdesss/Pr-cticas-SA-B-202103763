# Informe de la prueba de DR — sistema Aroma (P9)

Jennifer Taperio · 202103763 · pruebas del 17/10/2026, hora de Guatemala (UTC-6). Evidencias en `P9/evidencias/`.

## 1. Objetivos declarados

Se declararon **antes** de medir, en `P9/dr/OBJETIVOS-RTO-RPO.md` (commit `7f660d7`).
- **RTO = 15 min.** Va desde que corre `bootstrap.ps1` sobre un clúster destruido hasta `/api/salud` = 200 **con los datos restaurados**. El ensayo sin BD ni servicios tardó 5:07; para el sistema completo se estimaron 8–12 min, más un margen por la descarga de imágenes. Para un café, 15 minutos sin sistema son tolerables, porque se pueden tomar pedidos en papel.
- **RPO = 1 h.** Lo sostiene el Schedule `respaldo-horario-aroma` (cada hora, retención 48 h, con volúmenes y un hook `pg_dumpall`). Una hora de pedidos se reconstruye con los tickets del turno. Un RPO menor exigiría archivar el WAL fuera del clúster.

## 2. Escenario ejecutado

1. **Nodo (01:37):** `kubectl drain` del worker que alojaba la **primaria** de PostgreSQL. Mientras tanto, un cliente consultaba `/api/salud` y leía la BD cada segundo.
2. **Clúster completo (02:40 y 03:02):** `kind delete cluster` borró nodos, ArgoCD, Velero, la BD y sus volúmenes. Quedaron intactos MinIO (los respaldos), el estado en HCP Terraform y la copia cifrada de la llave. La recuperación fue `bootstrap.ps1` y después `restaurar-datos.ps1`.
3. **Datos (00:58):** se crearon pedidos marcados antes y después del respaldo, que terminó a las 00:58:08. Luego se borró el `postgresql`, con su StatefulSet y sus PVC, y se restauró.

## 3. Tiempos medidos

| Prueba (registro) | Marcas de tiempo | Resultado |
|---|---|---|
| Nodo (`prueba-perdida-nodo-20261017-013734.log`) | Drenaje 01:37:58–01:38:44; uncordon 01:39:45; 2/2 instancias a las 01:40:00 | **96.48 %** disponible (192/199); una ventana de **7.5 s** de 503; failover de Patroni |
| Reconstrucción 1 (`…-024040.log`) | t0 02:40:48.859 → bootstrap 02:48:56 (8:07) → restauración fallida → script corregido → datos verificados 02:52:17 | **RTO 11:28 con intervención** |
| Reconstrucción 2 (`…-030258.log`) | t0 03:03:04.748 → bootstrap 03:13:00 (9:55) → restore 03:13:33, solo en la primaria → tiempo agotado 03:23:43 | **RTO 20:38, NO CUMPLE** |
| Datos (`bloque-8b-ensayo-restauracion.txt`) | Borrado 00:58:18 → restore 01:15:32 → BD Running 01:24:40 | Contenido verificado, tras 2 defectos corregidos en el camino |

## 4. Pérdida medida

- **RPO real: 10 s** (respaldo 00:58:08, pérdida 00:58:18).
  - **Se recuperaron** los 9 productos y los 3 pedidos `ENSAYO-ANTES`, en la primaria y en la réplica, con bytes de `pgdata` idénticos a los respaldados.
  - **Se perdieron** los 2 pedidos `ENSAYO-DESPUES`, porque se escribieron después del respaldo. Es la pérdida que el RPO admite.
- **Reconstrucciones:** 0 de 4 pedidos perdidos. Los respaldos de las 08:00 y 09:00 UTC tenían todo, porque no hubo escrituras posteriores.
- **Nodo:** sin pérdida, porque Patroni preservó la primaria.

## 5. Puntos únicos de fallo detectados

1. **Una sola máquina.** Docker, MinIO y la copia DPAPI de la llave están en la misma laptop. Docker Desktop se detuvo solo dos veces.
2. **La restauración depende del orden** entre ArgoCD, el operador, Velero y el recolector de basura:
   - Intento 1: la BD nueva se retiró mientras el operador todavía la creaba.
   - Intento 2: el recolector de basura borró un pod restaurado (por su `ownerReference` viejo) y el operador generó contraseñas nuevas, distintas de las de los datos.
3. **Un respaldo "Completed" sin datos.** Con la StorageClass de kind (PV `hostPath`), Velero omitía `pgdata` sin error. Se corrigió con `aroma-local`; los respaldos anteriores a las 06:30 UTC no sirven.
4. **La salud no refleja la BD.** `/api/salud` dio 200 con la BD vacía mientras los pedidos daban 503.
5. **No hay rebalanceo tras un uncordon.** Todas las réplicas estaban en un solo nodo antes de drenar; una caída real de ese nodo las tumbaría todas.
6. **Dependencias externas para reconstruir:** GitHub, GHCR, Docker Hub y Helm. Dos imágenes de Bitnami retiradas rompieron componentes.
7. **La llave en MinIO no está cifrada en reposo**, y la copia DPAPI solo la abre una cuenta de Windows.

## 6. Brecha y plan

- **RTO:** la plataforma cumple (8:07 y 9:55), pero la recuperación con datos tomó 11:28 con intervención y 20:38 sin ella. **El RTO automático no quedó demostrado**, porque la restauración no es confiable sin intervención.
- **RPO:** cumple (10 s medidos, peor caso < 1 h).

**Plan, en orden de impacto:**
1. **Restauración independiente del orden.** Credenciales fijas de la BD como SealedSecrets en GitOps; restaurar solo los PVC y los pods, quitando el `ownerReference` con un *resource modifier* de Velero, y dejar que el operador cree el StatefulSet. Validarlo con 3 reconstrucciones seguidas sin intervención.
2. **Respaldo fuera de la máquina.** Replicar MinIO a otro equipo o a la nube con cifrado, y guardar la llave en un gestor externo, o migrar a External Secrets.
3. **Salud real.** Una *readiness* que consulte la BD y un `preStop`, para eliminar la ventana de 7.5 s.
4. **Distribución.** `topologySpreadConstraints` y un *descheduler* para rebalancear tras un uncordon.
5. **Menos dependencia externa.** Un registro espejo local de imágenes y charts.
