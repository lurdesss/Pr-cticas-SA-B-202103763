# ============================================================================
# Observa el despliegue canary del gateway (Argo Rollouts) y deja un
# registro con marcas de tiempo de cada cambio: paso actual, peso,
# replicas por version y resultado de cada AnalysisRun.
#
# No modifica nada: el canary lo dispara un commit en aroma-gitops que
# cambia charts/gateway/values-prod.yaml (imagen.tag); ArgoCD lo aplica.
#
# Uso:  powershell -ExecutionPolicy Bypass -File P9\dr\observar-canary.ps1 [-Registro <archivo>] [-Minutos 10]
# Termina cuando el Rollout queda Healthy con la version nueva al 100 %
# (codigo 0), si se aborta (codigo 1) o al agotar el tiempo (codigo 2).
# ============================================================================
param(
  [string]$Contexto = "kind-aroma-p9",
  [string]$Namespace = "aroma-prod",
  [string]$Rollout = "gateway",
  [string]$Registro = "",
  [int]$Minutos = 10
)
$ErrorActionPreference = "Continue"

function Linea([string]$t) {
  $l = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"), $t
  Write-Host $l
  if ($Registro) { Add-Content -Path $Registro -Value $l -Encoding utf8 }
}
function Kj([string[]]$a) { (& kubectl --context $Contexto @a 2>$null | Out-String) | ConvertFrom-Json }

# Se toma la version ESTABLE al iniciar (no la actual): si el canary ya
# empezo, la estable sigue siendo la anterior hasta que termina.
$inicioRev = (Kj @("get", "rollout", $Rollout, "-n", $Namespace, "-o", "json")).status.stableRS
Linea "Observando rollout/$Rollout en $Namespace (version estable inicial: $inicioRev)"
$limite = (Get-Date).AddMinutes($Minutos)
$ultimo = ""; $vistos = @{}
while ((Get-Date) -lt $limite) {
  $r = Kj @("get", "rollout", $Rollout, "-n", $Namespace, "-o", "json")
  $img = $r.spec.template.spec.containers[0].image
  $paso = $r.status.currentStepIndex
  $total = @($r.spec.strategy.canary.steps).Count
  $fase = $r.status.phase
  $estado = "fase=$fase paso=$paso/$total peso-canary=$($r.status.canary.weights.canary.weight) " +
            "estable=$($r.status.stableRS) canary=$($r.status.currentPodHash) " +
            "replicas listas=$($r.status.readyReplicas)/$($r.spec.replicas) imagen=$($img.Split(':')[-1])"
  if ($estado -ne $ultimo) { Linea $estado; $ultimo = $estado }

  foreach ($a in @((Kj @("get", "analysisrun", "-n", $Namespace, "-o", "json")).items)) {
    $clave = "$($a.metadata.name)|$($a.status.phase)"
    if (-not $vistos[$clave]) {
      $vistos[$clave] = $true
      $msg = @($a.status.metricResults | ForEach-Object { "$($_.name): $($_.phase) (exitos=$($_.successful) fallos=$($_.failed))" }) -join "; "
      Linea "AnalysisRun $($a.metadata.name): $($a.status.phase) $msg"
    }
  }

  if ($r.status.abort) { Linea "ABORTADO: $($r.status.message)"; exit 1 }
  if ($fase -eq "Healthy" -and $paso -eq $total -and $r.status.stableRS -eq $r.status.currentPodHash -and $r.status.stableRS -ne $inicioRev) {
    Linea "COMPLETADO: version nueva al 100 % y marcada como estable ($($r.status.stableRS))"
    exit 0
  }
  Start-Sleep -Seconds 5
}
Linea "Tiempo agotado ($Minutos min) sin completar ni abortar."
exit 2
