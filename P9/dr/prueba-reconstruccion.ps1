# ============================================================================
# Prueba de reconstruccion completa cronometrada -> RTO real.
#
# Escenario (desastre): se elimina el cluster kind completo
# (kind delete cluster). Sobreviven, por diseno, fuera del cluster:
# MinIO con los backups de Velero, el estado remoto de Terraform en HCP y la
# copia cifrada de la llave de Sealed Secrets.
#
# RTO medido (definicion de P9/dr/OBJETIVOS-RTO-RPO.md): desde que arranca
# P9/bootstrap.ps1 hasta que el gateway responde /api/salud = 200 CON los
# datos de produccion restaurados desde el ultimo respaldo de Velero.
#
#   1. Foto previa: pedidos existentes y ultimo backup horario.
#   2. DESASTRE: kind delete cluster --name aroma-p9.
#   3. RECUPERACION (cronometrada):
#        a) P9/bootstrap.ps1            (cluster, llave, ArgoCD, app-of-apps)
#        b) P9/dr/restaurar-datos.ps1   (PostgreSQL desde el ultimo backup)
#        c) P9/dr/verificar-secretos.ps1 (continuidad de secretos)
#   4. Comparacion de datos: pedidos recuperados y perdidos.
#
# Uso: powershell -ExecutionPolicy Bypass -File P9\dr\prueba-reconstruccion.ps1 [-Registro <archivo>]
# ============================================================================
param(
  [string]$Registro = "",
  [string]$Contexto = "kind-aroma-p9",
  [int]$ObjetivoMinutos = 15
)
$ErrorActionPreference = "Continue"
$p9 = Split-Path -Parent $PSScriptRoot
$ns = "aroma-prod"
if (-not $Registro) { $Registro = Join-Path $p9 ("evidencias\prueba-reconstruccion-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log") }

function Linea([string]$t) {
  $l = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff zzz"), $t
  Write-Host $l; Add-Content -Path $Registro -Value $l -Encoding utf8
}
function Kc { & kubectl --context $Contexto @args 2>$null }
function Pedidos {
  $pri = Kc get pods -n $ns -l "application=spilo,spilo-role=master" -o jsonpath='{.items[0].metadata.name}'
  if (-not $pri) { return @() }
  @(Kc exec -n $ns $pri -c postgres '--' psql -U postgres -d pedidos_db -At -c "select id || ' ' || creado_en || ' ' || coalesce(notas,'') from pedidos order by id;")
}

# --------------------------------------------------------- 1. foto previa
Linea "PRUEBA DE RECONSTRUCCION COMPLETA (objetivo RTO: $ObjetivoMinutos min)"
$antes = Pedidos
Linea "pedidos antes del desastre: $($antes.Count)"
$antes | ForEach-Object { Add-Content -Path $Registro -Value "    $_" -Encoding utf8 }
$ultimo = (((& kubectl --context $Contexto get backups.velero.io -n velero -l velero.io/schedule-name=respaldo-horario-aroma -o json 2>$null) | Out-String) | ConvertFrom-Json).items |
  Where-Object { $_.status.phase -eq "Completed" } | Sort-Object { $_.status.completionTimestamp } | Select-Object -Last 1
Linea "ultimo backup horario Completed: $($ultimo.metadata.name) (completado $($ultimo.status.completionTimestamp))"

# ------------------------------------------------------------ 2. desastre
Linea "DESASTRE: kind delete cluster --name aroma-p9"
& kind delete cluster --name aroma-p9 2>&1 | ForEach-Object { Add-Content -Path $Registro -Value "    $_" -Encoding utf8 }
Linea "cluster eliminado (MinIO, estado HCP y copia de la llave quedan fuera del cluster)"

# ---------------------------------------------------- 3. recuperacion
$inicio = Get-Date
Linea "RECUPERACION inicio (t=0): P9/bootstrap.ps1"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $p9 "bootstrap.ps1") | Out-Null
$okBootstrap = $LASTEXITCODE -eq 0
$logBootstrap = Get-ChildItem (Join-Path $p9 "evidencias\bootstrap-*.log") | Sort-Object LastWriteTime | Select-Object -Last 1
Linea ("bootstrap terminado (exito={0}) a t={1:mm\:ss}; registro: {2}" -f $okBootstrap, ((Get-Date) - $inicio), $logBootstrap.Name)
if (-not $okBootstrap) { Linea "FALLA: el bootstrap no termino; se detiene la prueba"; exit 1 }

Linea "restauracion de datos: P9/dr/restaurar-datos.ps1"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "restaurar-datos.ps1") -Registro $Registro
$okDatos = $LASTEXITCODE -eq 0
Linea ("restauracion de datos terminada (exito={0}) a t={1:mm\:ss}" -f $okDatos, ((Get-Date) - $inicio))

$fin = Get-Date
$rto = $fin - $inicio
Linea ("RECUPERACION fin: RTO medido = {0:hh\:mm\:ss} ({1:N0} s) | objetivo {2} min -> {3}" -f
  $rto, $rto.TotalSeconds, $ObjetivoMinutos, $(if ($okDatos -and $rto.TotalMinutes -le $ObjetivoMinutos) { "CUMPLE" } else { "NO CUMPLE" }))

Linea "continuidad de secretos tras la reconstruccion: P9/dr/verificar-secretos.ps1"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "verificar-secretos.ps1") -Registro $Registro | Out-Null

# -------------------------------------------------- 4. comparacion de datos
$despues = Pedidos
$perdidos = @($antes | Where-Object { $despues -notcontains $_ })
Linea "pedidos despues de la recuperacion: $($despues.Count) | recuperados: $($antes.Count - $perdidos.Count) de $($antes.Count) | perdidos: $($perdidos.Count)"
$perdidos | ForEach-Object { Add-Content -Path $Registro -Value "    perdido: $_" -Encoding utf8 }
Linea "FIN prueba de reconstruccion"
