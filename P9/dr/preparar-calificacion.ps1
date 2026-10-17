# ============================================================================
# Deja el sistema listo para la calificacion y dice que esta bien y que no.
# No destruye nada salvo, si se pide, la restauracion de la BD desde el
# ultimo backup horario (necesaria: el Restore que exige el criterio 2.6 lo
# borra Velero cuando expira su backup, a las 48 h).
#
#   1. Docker, contexto de kubectl, nodos, MinIO.
#   2. ArgoCD: todas las Applications Synced/Healthy (refresca la raiz).
#   3. Velero: BSL Available, ultimo backup horario Completed con pgdata.
#   4. Restauracion de datos (crea el Restore del dia), salvo -SinRestaurar.
#   5. Continuidad de secretos (5 comprobaciones).
#   6. Comando para correr el verificador oficial.
#
# Uso: powershell -ExecutionPolicy Bypass -File P9\dr\preparar-calificacion.ps1 [-SinRestaurar]
# ============================================================================
param(
  [switch]$SinRestaurar,
  [string]$Contexto = "kind-aroma-p9"
)
$ErrorActionPreference = "Continue"
$p9 = Split-Path -Parent $PSScriptRoot
$problemas = 0
function Ok([string]$t) { Write-Host "  [OK]    $t" -ForegroundColor Green }
function Mal([string]$t) { Write-Host "  [FALLA] $t" -ForegroundColor Red; $script:problemas++ }
function Kj { ((& kubectl --context $Contexto @args -o json 2>$null) | Out-String) | ConvertFrom-Json }

Write-Host "`n=== 1. Infraestructura local"
docker info --format "{{.ServerVersion}}" 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { Ok "Docker Desktop en ejecucion" } else { Mal "Docker Desktop detenido: abralo y espere 'Engine running'"; exit 1 }
$ctx = kubectl config current-context 2>$null
if ($ctx -eq $Contexto) { Ok "contexto de kubectl: $ctx" } else { Mal "contexto actual '$ctx'; ejecute: kubectl config use-context $Contexto" }
$nodos = @((Kj get nodes).items)
$listos = @($nodos | Where-Object { ($_.status.conditions | Where-Object type -eq "Ready").status -eq "True" })
if ($nodos.Count -ge 3 -and $listos.Count -eq $nodos.Count) { Ok "$($listos.Count) nodos Ready" } else { Mal "nodos Ready: $($listos.Count)/$($nodos.Count) (si el cluster no existe: P9\bootstrap.ps1)" }
$minio = docker inspect -f "{{.State.Running}}" minio 2>$null
if ($minio -eq "true") { Ok "MinIO (almacen de respaldos, fuera del cluster) en ejecucion" } else { Mal "MinIO detenido: docker start minio" }

Write-Host "`n=== 2. ArgoCD"
& kubectl --context $Contexto annotate application aroma-root -n argocd argocd.argoproj.io/refresh=hard --overwrite 2>$null | Out-Null
$limite = (Get-Date).AddMinutes(5)
do {
  Start-Sleep -Seconds 10
  $apps = @((Kj get applications -n argocd).items)
  $malas = @($apps | Where-Object { $_.status.sync.status -ne "Synced" -or $_.status.health.status -ne "Healthy" })
} until ($malas.Count -eq 0 -or (Get-Date) -gt $limite)
if ($malas.Count -eq 0) { Ok "$($apps.Count) Applications Synced/Healthy (raiz aroma-root incluida)" }
else { $malas | ForEach-Object { Mal "Application $($_.metadata.name): $($_.status.sync.status)/$($_.status.health.status)" } }

Write-Host "`n=== 3. Velero"
$bsl = Kj get backupstoragelocations.velero.io default -n velero
if ($bsl.status.phase -eq "Available") { Ok "destino de respaldos 'default' Available (MinIO)" } else { Mal "BSL default: $($bsl.status.phase)" }
$ultimo = @((Kj get backups.velero.io -n velero -l velero.io/schedule-name=respaldo-horario-aroma).items |
  Where-Object { $_.status.phase -eq "Completed" } | Sort-Object { $_.status.completionTimestamp }) | Select-Object -Last 1
if ($ultimo) { Ok "ultimo backup horario Completed: $($ultimo.metadata.name) ($($ultimo.status.completionTimestamp))" } else { Mal "no hay backup horario Completed" }
$llaves = @((Kj get backups.velero.io -n velero).items | Where-Object { $_.status.phase -eq "Completed" -and $_.spec.includedNamespaces -contains "kube-system" })
if ($llaves.Count) { Ok "backup de la llave (kube-system) Completed: $($llaves.Count)" } else { Mal "no hay backup Completed de kube-system: velero backup create llaves-hoy --from-schedule respaldo-llaves --wait" }

Write-Host "`n=== 4. Restauracion de datos (Restore que exige el criterio 2.6)"
if ($SinRestaurar) {
  $rs = @((Kj get restores.velero.io -n velero).items | Where-Object { $_.status.phase -in @("Completed", "PartiallyFailed") })
  if ($rs.Count) { Ok "Restore existente: $($rs[0].metadata.name)" } else { Mal "no hay Restore Completed; ejecute sin -SinRestaurar" }
} else {
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "restaurar-datos.ps1")
  if ($LASTEXITCODE -eq 0) { Ok "restauracion verificada (Restore creado)" } else { Mal "la restauracion fallo: ver RUNBOOK.md seccion 4.5" }
}

Write-Host "`n=== 5. Continuidad de secretos"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "verificar-secretos.ps1") | Out-Null
if ($LASTEXITCODE -eq 0) { Ok "5/5 comprobaciones (llave = copia de respaldo, SealedSecret descifrado, Velero autenticado)" } else { Mal "continuidad de secretos con fallas: ejecute P9\dr\verificar-secretos.ps1" }

Write-Host "`n=== Resultado: $(if ($problemas -eq 0) { 'LISTO para calificar' } else { "$problemas problema(s) por resolver" })"
Write-Host "Verificador (Git Bash, desde una carpeta FUERA del repo con p9.conf; plantilla en P9/pruebas/p9.conf):"
$rutaBash = $p9 -replace '\\', '/'
$rutaBash = "/" + $rutaBash.Substring(0, 1).ToLower() + $rutaBash.Substring(2)
Write-Host "  bash `"$rutaBash/docs/verificar_p9.sh`""
exit [int]($problemas -gt 0)
