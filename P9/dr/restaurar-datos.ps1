# ============================================================================
# Restaura los datos de PostgreSQL (aroma-pg, namespace aroma-prod) desde un
# backup de Velero. Procedimiento ensayado en el Bloque 8b
# (P9/evidencias/bloque-8b-ensayo-restauracion.txt); cada paso responde a
# un fallo real encontrado en ese ensayo.
#
#   1. Valida que el backup este Completed y que respalde pgdata con bytes
#      (un backup "Completed" puede no contener los datos: Bloque 8a).
#   2. Pausa la reconciliacion de ArgoCD en aroma-bd (si no, ArgoCD recrea
#      un PostgreSQL vacio mientras se restaura).
#   3. Borra el postgresql actual (si existe): el operador elimina
#      StatefulSet, pods y PVC. Velero no sobrescribe un PVC existente.
#   4. velero restore: PVC con datos (Kopia + init container restore-wait),
#      StatefulSet, pods, Secrets y configuracion de Patroni.
#   5. Reanuda aroma-bd (ArgoCD recrea el recurso postgresql).
#   6. Reinicia el operador de Zalando: su evento de creacion falla con los
#      objetos ya restaurados (CreateFailed) y solo una sincronizacion
#      completa al arrancar los adopta.
#   7. Reinicia los pods de los servicios con BD (leen la contrasena
#      restaurada y reabren conexiones; su /salud no detecta una BD rota).
#   8. Verifica: postgresql Running, 2 instancias listas, gateway 200.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File P9\dr\restaurar-datos.ps1 [-Respaldo <nombre>] [-Registro <archivo>]
# Sin -Respaldo usa el backup Completed mas reciente del Schedule
# respaldo-horario-aroma que contenga pgdata.
# Codigo de salida 0 si la restauracion queda verificada; 1 si falla.
# ============================================================================
param(
  [string]$Respaldo = "",
  [string]$Registro = "",
  [string]$Contexto = "kind-aroma-p9",
  [int]$MinutosEspera = 10
)
$ErrorActionPreference = "Continue"
$velero = if (Get-Command velero -ErrorAction SilentlyContinue) { "velero" } else { "C:\HerramientasKubernetes\velero.exe" }
$ns = "aroma-prod"

function Linea([string]$t) {
  $l = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"), $t
  Write-Host $l
  if ($Registro) { Add-Content -Path $Registro -Value $l -Encoding utf8 }
}
function Kc { & kubectl --context $Contexto @args 2>$null }
function Kj { ((& kubectl --context $Contexto @args -o json 2>$null) | Out-String) | ConvertFrom-Json }
function Detener([string]$t) { Linea "FALLA: $t"; exit 1 }
function Esperar([scriptblock]$cond, [string]$desc) {
  $limite = (Get-Date).AddMinutes($MinutosEspera)
  while ((Get-Date) -lt $limite) { if (& $cond) { return $true }; Start-Sleep -Seconds 5 }
  Detener "tiempo agotado esperando: $desc"
}

Linea "INICIO restauracion de datos de PostgreSQL (aroma-pg)"

# ---------------------------------------------------- 1. elegir y validar backup
# Tras una reconstruccion, Velero re-sincroniza desde MinIO los objetos
# Backup pero no los PodVolumeBackup del cluster anterior. Si existen, se
# exige que el backup contenga pgdata con bytes; si no existen, se avisa y
# la comprobacion se hace despues del restore (PodVolumeRestores de pgdata).
$hayPvbs = @((Kj get podvolumebackups.velero.io -n velero).items).Count -gt 0
if (-not $Respaldo) {
  $candidatos = @((Kj get backups.velero.io -n velero -l velero.io/schedule-name=respaldo-horario-aroma).items |
    Where-Object { $_.status.phase -eq "Completed" } | Sort-Object { $_.status.completionTimestamp } -Descending)
  foreach ($c in $candidatos) {
    if (-not $hayPvbs) { $Respaldo = $c.metadata.name; break }
    $pv = @((Kj get podvolumebackups.velero.io -n velero -l "velero.io/backup-name=$($c.metadata.name)").items |
      Where-Object { $_.spec.volume -eq "pgdata" -and $_.status.phase -eq "Completed" -and $_.status.progress.totalBytes -gt 0 })
    if ($pv.Count -ge 1) { $Respaldo = $c.metadata.name; break }
  }
  if (-not $Respaldo) { Detener "no hay un backup Completed de respaldo-horario-aroma que contenga pgdata" }
}
$bk = Kj get backups.velero.io $Respaldo -n velero
if ($bk.status.phase -ne "Completed") { Detener "el backup $Respaldo no esta Completed ($($bk.status.phase))" }
if ($hayPvbs) {
  $pvbs = @((Kj get podvolumebackups.velero.io -n velero -l "velero.io/backup-name=$Respaldo").items | Where-Object { $_.spec.volume -eq "pgdata" })
  if ($pvbs.Count -lt 1 -or ($pvbs | Where-Object { -not ($_.status.progress.totalBytes -gt 0) })) {
    Detener "el backup $Respaldo no contiene pgdata con datos (backup sin volumen de PostgreSQL)"
  }
  Linea ("backup elegido: $Respaldo (completado $($bk.status.completionTimestamp); pgdata: " +
    (($pvbs | ForEach-Object { "$($_.spec.pod.name)=$($_.status.progress.totalBytes) bytes" }) -join ", ") + ")")
} else {
  Linea "backup elegido: $Respaldo (completado $($bk.status.completionTimestamp)); AVISO: sin PodVolumeBackups en el cluster (reconstruido), pgdata se valida despues del restore"
}

# ------------------------------------------------------- 2. pausar ArgoCD
Linea "PASO 2 pausar la reconciliacion de ArgoCD en aroma-bd"
Kc annotate application aroma-bd -n argocd argocd.argoproj.io/skip-reconcile=true --overwrite | Out-Null

# ------------------------------------------------ 3. retirar la BD actual
Linea "PASO 3 retirar el PostgreSQL actual (StatefulSet, pods y PVC)"
if (Kc get postgresql aroma-pg -n $ns -o name) { Kc delete postgresql aroma-pg -n $ns --wait=true --timeout=180s | Out-Null }
Esperar { -not (Kc get sts,pvc,pods -n $ns -l cluster-name=aroma-pg -o name) } "que el operador borre StatefulSet, pods y PVC" | Out-Null
Linea "BD retirada"

# ----------------------------------------------------------- 4. restore
$nombreRestore = "restaurar-aroma-pg-" + (Get-Date -Format "yyyyMMdd-HHmmss")
Linea "PASO 4 velero restore $nombreRestore desde $Respaldo"
& $velero restore create $nombreRestore --from-backup $Respaldo --include-namespaces $ns --selector cluster-name=aroma-pg 2>&1 | Out-Null
Esperar { (Kj get restores.velero.io $nombreRestore -n velero).status.phase -in @("Completed", "PartiallyFailed", "Failed") } "fin del restore" | Out-Null
$rs = Kj get restores.velero.io $nombreRestore -n velero
$pvrs = @((Kj get podvolumerestores.velero.io -n velero -l "velero.io/restore-name=$nombreRestore").items | Where-Object { $_.spec.volume -eq "pgdata" })
Linea ("restore $($rs.status.phase): items $($rs.status.progress.itemsRestored)/$($rs.status.progress.totalItems), advertencias $($rs.status.warnings); pgdata restaurado: " +
  (($pvrs | ForEach-Object { "$($_.spec.pod.name)=$($_.status.phase) $($_.status.progress.bytesDone) bytes" }) -join ", "))
if ($rs.status.phase -eq "Failed" -or $pvrs.Count -lt 1 -or
    ($pvrs | Where-Object { $_.status.phase -ne "Completed" -or -not ($_.status.progress.bytesDone -gt 0) })) {
  Detener "el restore no recupero pgdata con datos"
}

# -------------------------------------------------------- 5. reanudar ArgoCD
Linea "PASO 5 reanudar aroma-bd (revision $((Kj get application aroma-bd -n argocd).status.sync.revision.Substring(0,7)))"
Kc annotate application aroma-bd -n argocd argocd.argoproj.io/skip-reconcile- | Out-Null
Esperar { Kc get postgresql aroma-pg -n $ns -o name } "que ArgoCD recree el recurso postgresql" | Out-Null

# ------------------------------------------- 6. sincronizacion del operador
Linea "PASO 6 reiniciar el operador de Zalando (sincronizacion completa sobre lo restaurado)"
Kc delete pod -n postgres-operator -l app.kubernetes.io/name=postgres-operator --wait=false | Out-Null
Esperar { (Kj get postgresql aroma-pg -n $ns).status.PostgresClusterStatus -eq "Running" -and
          (Kj get sts aroma-pg -n $ns).status.readyReplicas -eq 2 } "postgresql Running con 2 instancias listas" | Out-Null
Linea "postgresql Running, 2 instancias listas"

# -------------------------------------------- 7. reconectar los servicios
Linea "PASO 7 reiniciar los pods de catalogo, inventario, pedidos y resenas"
foreach ($s in "catalogo", "inventario", "pedidos", "resenas") { Kc delete pods -n $ns -l "app.kubernetes.io/name=$s" --wait=false | Out-Null }
foreach ($s in "catalogo", "inventario", "pedidos", "resenas") { Kc rollout status "deploy/$s" -n $ns --timeout=300s | Out-Null }

# --------------------------------------------------------- 8. verificacion
$pf = Start-Process kubectl -ArgumentList "--context $Contexto port-forward -n $ns svc/gateway 18001:8000" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 4
try { $codigo = (Invoke-WebRequest http://127.0.0.1:18001/api/salud -UseBasicParsing -TimeoutSec 10).StatusCode } catch { $codigo = "error" }
Stop-Process -Id $pf.Id -Force -ErrorAction SilentlyContinue
$pri = (Kj get pods -n $ns -l "application=spilo,spilo-role=master").items[0].metadata.name
$productos = Kc exec -n $ns $pri -c postgres -- psql -U postgres -d catalogo_db -At -c "select count(*) from productos;"
$pedidos = Kc exec -n $ns $pri -c postgres -- psql -U postgres -d pedidos_db -At -c "select count(*) from pedidos;"
Linea "VERIFICACION: gateway /api/salud=$codigo | primaria=$pri | productos=$productos | pedidos=$pedidos"
if ($codigo -ne 200) { Detener "el gateway no responde 200 tras la restauracion" }
Linea "FIN restauracion verificada (restore $nombreRestore desde $Respaldo)"
exit 0
