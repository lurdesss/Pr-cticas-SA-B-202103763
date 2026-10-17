# Runbook de recuperación — sistema Aroma (P9)

Procedimiento para recuperar el sistema **sin ayuda de la autora**. Cada paso tiene: el **comando** exacto, la **verificación** de que funcionó y **qué hacer si falla**. Todos los comandos se ejecutan en **PowerShell desde la raíz del repositorio de código**, salvo que se indique Git Bash.

> **Regla de oro:** antes de actuar, identifique el escenario en la sección 2. No ejecute pruebas destructivas (`P9/dr/prueba-*.ps1`) durante un incidente real.

---

## 0. Qué existe fuera del clúster (y debe seguir existiendo)

Un desastre en Kubernetes **no** destruye estos elementos, y la recuperación depende de ellos:

| Elemento | Dónde | Cómo comprobarlo |
|---|---|---|
| Estado de Terraform (con bloqueo) | HCP Terraform, org `VerdictCorp`, workspace `aroma-p9-infra` | `terraform -chdir=P9\terraform state list` (tras el paso 1.3) |
| Respaldos de Velero | Contenedor Docker `minio`, bucket `velero-backups`, volumen `aroma-p9-minio` | `docker ps --filter name=minio` → `Up` |
| Llave de Sealed Secrets (copia cifrada DPAPI) | `%USERPROFILE%\.aroma-p9\sealed-secrets-llave.dpapi` (solo la descifra la cuenta de Windows de esta máquina) | `Test-Path "$env:USERPROFILE\.aroma-p9\sealed-secrets-llave.dpapi"` → `True` |
| Configuración deseada | GitHub `lurdesss/aroma-gitops` (rama `main`) y este repositorio | se abren en el navegador sin iniciar sesión |
| Imágenes de los servicios | GHCR `ghcr.io/lurdesss/pr-cticas-sa-b-202103763/<servicio>:v1.0.0` (públicas) | `docker manifest inspect ghcr.io/lurdesss/pr-cticas-sa-b-202103763/gateway:v1.0.0` |

**Si falta la copia de la llave**, vaya a la sección 6 **antes** de reconstruir.

---

## 1. Requisitos (una sola vez por máquina)

| # | Paso | Comando | Verificación |
|---|---|---|---|
| 1.1 | Herramientas en el PATH | `docker version; kind version; terraform version; kubectl version --client; helm version` | todos imprimen su versión. Velero CLI: `C:\HerramientasKubernetes\velero.exe version --client-only` |
| 1.2 | Docker Desktop en ejecución | abrir Docker Desktop y esperar *Engine running* | `docker info --format "{{.ServerVersion}}"` imprime una versión |
| 1.3 | Credencial de HCP Terraform | `terraform login` (solo si no existe `%APPDATA%\terraform.d\credentials.tfrc.json`) | `$env:TF_WORKSPACE="default"; terraform -chdir=P9\terraform init` → `Terraform has been successfully initialized!` |
| 1.4 | MinIO arriba | `docker start minio` (si estaba detenido) | `curl.exe -s -o NUL -w "%{http_code}" http://127.0.0.1:9000/minio/health/live` → `200` |

---

## 2. Identificar el escenario

```powershell
kubectl config current-context        # esperado: kind-aroma-p9
kubectl get nodes                     # 3 nodos Ready
kubectl get applications -n argocd    # todas Synced / Healthy
kubectl get postgresql -n aroma-prod  # STATUS Running
```

| Lo que observa | Escenario | Sección |
|---|---|---|
| `kind get clusters` no muestra `aroma-p9`, o el API no responde con Docker arriba | **Pérdida total del clúster** | 3 |
| El clúster está bien pero faltan datos o están corruptos (pedidos borrados, BD vacía) | **Pérdida de datos** | 4 |
| Un nodo `NotReady`, o mantenimiento planificado de un nodo | **Pérdida o mantenimiento de nodo** | 5 |
| SealedSecrets con `Synced=False` / Secret `velero-minio-credentials` ausente | **Llave de Sealed Secrets** | 6 |
| Docker Desktop detenido (`failed to connect to the docker API`) | Abra Docker Desktop: los 3 nodos y MinIO arrancan solos; vuelva a la sección 2 | — |

---

## 3. Pérdida total del clúster (reconstrucción desde cero)

**Orden de dependencias** (no lo altere): Docker → MinIO → estado HCP → clúster kind → **llave de Sealed Secrets** → ArgoCD → aroma-root → (olas) Sealed Secrets → Secret de MinIO → Velero/Kyverno/Rollouts/operador → Schedules/políticas → PostgreSQL → microservicios → **restauración de datos**.

| # | Paso | Comando | Verificación | Si falla |
|---|---|---|---|---|
| 3.1 | Requisitos | sección 1 completa | 1.1–1.4 OK | — |
| 3.2 | Bootstrap (≈ 8–10 min, un solo comando) | `powershell -ExecutionPolicy Bypass -File P9\bootstrap.ps1` | última línea `FIN bootstrap P9: duracion ...`; registro en `P9\evidencias\bootstrap-<fecha>.log` | lea la línea `FALLA:` del registro: indica el paso. `terraform init` → paso 1.3; `apps no llegaron a Synced/Healthy` → 3.6 |
| 3.3 | Llave restaurada (la hace el bootstrap) | `powershell -ExecutionPolicy Bypass -File P9\dr\verificar-secretos.ps1` | `Resultado: continuidad de secretos VERIFICADA` (5 OK) | sección 6 |
| 3.4 | Plataforma completa | `kubectl get applications -n argocd` | 15 Applications Synced/Healthy | 3.6 |
| 3.5 | **Restaurar los datos** (el clúster nuevo nace con la BD vacía) | sección 4 | sección 4 | sección 4 |
| 3.6 | Application que no se sincroniza | `kubectl get application <app> -n argocd -o jsonpath='{.status.operationState.message}'` | mensaje de error concreto | `waiting for completion of hook` largo → `kubectl patch application <app> -n argocd --type merge -p '{\"status\":{\"operationState\":{\"phase\":\"Terminating\"}}}'`. `aroma-root` OutOfSync intermitente → `kubectl annotate application aroma-root -n argocd argocd.argoproj.io/refresh=hard --overwrite`. Imagen `ImagePullBackOff` → `kubectl describe pod <pod> -n <ns>` (imágenes Bitnami retiradas: usar `bitnamilegacy/`) |

**Requiere internet:** la reconstrucción descarga charts (ArgoCD, Velero, Kyverno…), el repo GitOps de GitHub y las imágenes de GHCR y Docker Hub.

---

## 4. Pérdida de datos (restauración de PostgreSQL desde Velero)

**Qué se pierde:** lo escrito después del último respaldo horario (RPO objetivo: 1 h).

| # | Paso | Comando | Verificación | Si falla |
|---|---|---|---|---|
| 4.1 | Elegir el respaldo | `kubectl get backups.velero.io -n velero -l velero.io/schedule-name=respaldo-horario-aroma --sort-by=.status.completionTimestamp` | el último en `Completed` | si todos fallan, use `respaldo-diario-aroma-*` con `-Respaldo <nombre>` |
| 4.2 | Confirmar que el respaldo **tiene datos** (no basta "Completed") | `kubectl get podvolumebackups.velero.io -n velero -l velero.io/backup-name=<respaldo>` | 2 filas `pgdata` en `Completed` con BYTES > 0 | elija un respaldo anterior. Tras una reconstrucción estas filas pueden no existir: el script lo valida después |
| 4.3 | Restaurar (≈ 2 min) | `powershell -ExecutionPolicy Bypass -File P9\dr\restaurar-datos.ps1` (opcional: `-Respaldo <nombre>`) | última línea `FIN restauracion verificada`; antes `pgdata restaurado: aroma-pg-0=Completed ... bytes` | ver 4.5 |
| 4.4 | Verificar el contenido | `kubectl exec -n aroma-prod aroma-pg-0 -c postgres -- psql -U postgres -d catalogo_db -c "select count(*) from productos;"` | 9 productos; pedidos: `... -d pedidos_db -c "select id, creado_en, notas from pedidos order by id;"` | 4.5 |
| 4.5 | Problemas conocidos | | | |
| | Restore `InProgress` que no avanza (init `restore-wait` en error) | `kubectl rollout restart deploy/velero -n velero` | al arrancar, Velero marca `Failed` el restore atascado | revise `kubectl get cm velero-fs-restore-action-config -n velero -o jsonpath='{.data.image}'` = `velero/velero-restore-helper:v1.15.0` |
| | `postgresql` en `CreateFailed` / `UpdateFailed` | `kubectl rollout restart deploy/postgres-operator -n postgres-operator` | `kubectl get postgresql -n aroma-prod` → `Running` | — |
| | Réplica sin arrancar (`password authentication failed for user "standby"`) | alinear contraseñas con sus Secrets (Git Bash, no imprime valores): `for u in postgres standby aroma; do pw=$(kubectl get secret $u.aroma-pg.credentials.postgresql.acid.zalan.do -n aroma-prod -o jsonpath='{.data.password}' \| base64 -d); printf "ALTER ROLE %s WITH PASSWORD '%s';" $u "$pw" \| MSYS_NO_PATHCONV=1 kubectl exec -i -n aroma-prod aroma-pg-0 -c postgres -- psql -U postgres -q; done` y reiniciar el operador | `kubectl get sts aroma-pg -n aroma-prod` → `2/2` | — |
| | El script terminó en `FALLA` | lea el `AVISO`: `aroma-bd` queda **en pausa** para reintentar | reintente 4.3; para abandonar: `kubectl annotate application aroma-bd -n argocd argocd.argoproj.io/skip-reconcile-` | — |
| 4.6 | Servicios reconectados | `kubectl port-forward -n aroma-prod svc/gateway 18000:8000` y en otra consola `curl.exe http://127.0.0.1:18000/api/salud` | HTTP 200 con 4 dependencias `arriba`. **Ojo:** `/api/salud` no consulta la BD; confirme con 4.4 | `kubectl delete pods -n aroma-prod -l app.kubernetes.io/name=catalogo` (igual para inventario, pedidos, resenas) |

---

## 5. Pérdida o mantenimiento de un nodo

El servicio sigue respondiendo (medido: 96.48 % de disponibilidad, una ventana de 7.5 s).

| # | Paso | Comando | Verificación |
|---|---|---|---|
| 5.1 | Ver qué hay en el nodo y quién es la primaria | `kubectl get pods -n aroma-prod -o wide` y `kubectl get pods -n aroma-prod -l application=spilo -L spilo-role` | se conoce el nodo de la primaria |
| 5.2 | (Opcional, recomendado) mover la primaria antes de drenar | `kubectl exec -n aroma-prod <primaria> -c postgres -- patronictl switchover --leader <primaria> --candidate <replica> --force` | `kubectl exec -n aroma-prod <replica> -c postgres -- patronictl list`: Leader en el otro nodo |
| 5.3 | Drenar | `kubectl drain <nodo> --ignore-daemonsets --delete-emptydir-data --grace-period=30 --timeout=300s` | `node/<nodo> drained`; los "Cannot evict pod ... disruption budget" son **normales** (los PDB esperan a que haya reemplazos) |
| 5.4 | Durante el drenaje | `kubectl get pods -n aroma-prod -o wide` | réplicas en el otro worker; la instancia de PostgreSQL del nodo queda `Pending` (su volumen es local al nodo): es esperado |
| 5.5 | Devolver el nodo | `kubectl uncordon <nodo>` | `kubectl get sts aroma-pg -n aroma-prod` → `2/2` |
| 5.6 | **Rebalancear** (Kubernetes no lo hace solo) | `kubectl rollout restart deploy -n aroma-prod` y, para el gateway (Rollout), `kubectl patch rollout gateway -n aroma-prod --type merge -p '{\"spec\":{\"restartAt\":\"<hora UTC actual, ej. 2026-11-26T10:00:00Z>\"}}'` | `kubectl get pods -n aroma-prod -o wide`: réplicas repartidas entre los 2 workers |

---

## 6. Llave de Sealed Secrets

| Situación | Acción |
|---|---|
| **Respaldo preventivo** (tras instalar por primera vez o si el controlador rota la llave) | `powershell -ExecutionPolicy Bypass -File P9\scripts\exportar-llave-sealed-secrets.ps1` → `Llaves exportadas: N` |
| Restaurar en un clúster existente | `powershell -ExecutionPolicy Bypass -File P9\scripts\restaurar-llave-sealed-secrets.ps1` y luego `kubectl delete pod -n kube-system -l app.kubernetes.io/name=sealed-secrets` (el controlador recarga la llave) |
| Comprobar | `powershell -ExecutionPolicy Bypass -File P9\dr\verificar-secretos.ps1` → 5 OK |
| **La copia DPAPI se perdió o se cambió de máquina** | 1) Restaure desde Velero en un clúster con Velero operativo: `velero restore create --from-backup <manual-llaves-o-respaldo-llaves-*> --include-namespaces kube-system`. 2) Si tampoco existe: reconstruya con `P9\bootstrap.ps1 -PermitirLlaveNueva` y **vuelva a sellar** las credenciales de MinIO (`kubeseal`) en `aroma-gitops/secrets/velero-minio-credentials.yaml`: los SealedSecrets anteriores son ilegibles sin la llave original |

---

## 7. Comprobación final (después de cualquier recuperación)

```powershell
kubectl get nodes                                      # 3 Ready
kubectl get applications -n argocd                     # todas Synced/Healthy
kubectl get postgresql,sts -n aroma-prod               # Running, aroma-pg 2/2
kubectl get backupstoragelocations.velero.io -n velero # default Available
powershell -ExecutionPolicy Bypass -File P9\dr\verificar-secretos.ps1   # 5 OK
```
Y en Git Bash, desde una carpeta con `p9.conf` (ver `P9/GUIA-CALIFICACION.md`): `bash <repo>/P9/docs/verificar_p9.sh`.
