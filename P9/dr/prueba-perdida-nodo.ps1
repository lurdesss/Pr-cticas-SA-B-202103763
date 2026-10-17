# ============================================================================
# Prueba de perdida de nodo (criterio 2.5): drena un worker mientras se
# hacen peticiones continuas al gateway y registra cada respuesta.
#
# - Nodo drenado: por defecto el worker que aloja la PRIMARIA de PostgreSQL
#   (el caso mas exigente: Patroni debe promover la replica del otro nodo).
# - Cliente: corre dentro del contenedor del control-plane de kind (que no
#   se drena) con curl a la ClusterIP del Service del gateway. No se usa
#   "kubectl port-forward" porque se amarra a un solo pod y se cortaria al
#   drenar su nodo; tampoco se despliega nada en el cluster.
# - Dos sondas por segundo:
#     salud: GET /api/salud (gateway + 4 microservicios)
#     datos: POST /api/catalogo/graphql { productos } (lectura real de la BD)
# - Al terminar: disponibilidad de cada sonda y la mayor ventana de fallo
#   continuo, con marcas de tiempo del drenaje y del uncordon.
#
# Uso: powershell -ExecutionPolicy Bypass -File P9\dr\prueba-perdida-nodo.ps1 [-Nodo <worker>] [-Registro <archivo>]
# ============================================================================
param(
  [string]$Nodo = "",
  [string]$Registro = "",
  [string]$Contexto = "kind-aroma-p9",
  [int]$SegundosAntes = 20,
  [int]$SegundosDrenado = 60,
  [int]$SegundosDespues = 60
)
$ErrorActionPreference = "Continue"
$ns = "aroma-prod"
$cliente = "aroma-p9-control-plane"
if (-not $Registro) {
  $Registro = Join-Path (Split-Path -Parent $PSScriptRoot) ("evidencias\prueba-perdida-nodo-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
}
$sondas = [IO.Path]::ChangeExtension($Registro, ".sondas.txt")

function Linea([string]$t) {
  $l = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"), $t
  Write-Host $l; Add-Content -Path $Registro -Value $l -Encoding utf8
}
function Kc { & kubectl --context $Contexto @args 2>&1 }
function Volcar([string]$titulo, $salida) { Linea $titulo; $salida | ForEach-Object { Add-Content -Path $Registro -Value "    $_" -Encoding utf8 } }

# ------------------------------------------------------------ preparacion
$primaria = (Kc get pods -n $ns -l "application=spilo,spilo-role=master" -o jsonpath='{.items[0].metadata.name}')
if (-not $Nodo) { $Nodo = (Kc get pod $primaria -n $ns -o jsonpath='{.spec.nodeName}') }
$ip = (Kc get svc gateway -n $ns -o jsonpath='{.spec.clusterIP}')
Linea "INICIO prueba de perdida de nodo: se drena $Nodo (aloja la primaria $primaria); gateway ClusterIP $ip"
Volcar "estado inicial - pods de aroma-prod por nodo:" (Kc get pods -n $ns -o wide --no-headers | ForEach-Object { ($_ -split '\s+')[0, 2, 6] -join ' ' })
Volcar "estado inicial - Patroni:" (Kc exec -n $ns $primaria -c postgres '--' patronictl list)
Volcar "estado inicial - PDB:" (Kc get pdb -n $ns)

# Bucle de sondas dentro del control-plane: una linea por peticion
# "epoch_ms sonda codigo segundos". Se le pasa a bash por la entrada
# estandar (docker exec -i ... bash -s): pasarlo entre comillas por la
# linea de comandos de Windows es fragil, y "docker cp" a /tmp no sirve
# porque en los nodos de kind /tmp es un tmpfs (el archivo copiado queda
# debajo del montaje y el contenedor no lo ve; fallo real del primer intento).
$bucle = @'
#!/bin/bash
IP="$1"
while true; do
  t=$(date +%s%3N)
  r=$(curl -s -o /dev/null -m 3 -w '%{http_code} %{time_total}' "http://$IP:8000/api/salud") || r="000 3"
  echo "$t salud $r"
  t=$(date +%s%3N)
  r=$(curl -s -o /dev/null -m 3 -w '%{http_code} %{time_total}' -X POST -H 'Content-Type: application/json' -d '{"query":"{ productos { nombre } }"}' "http://$IP:8000/api/catalogo/graphql") || r="000 3"
  echo "$t datos $r"
  sleep 1
done
'@
$tmp = Join-Path $env:TEMP "p9-sondas.sh"
[IO.File]::WriteAllText($tmp, ($bucle -replace "`r`n", "`n"))
$proc = Start-Process docker -ArgumentList @("exec", "-i", $cliente, "bash", "-s", "--", $ip) `
  -RedirectStandardInput $tmp -RedirectStandardOutput $sondas -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 3
if (-not (Test-Path $sondas) -or (Get-Content $sondas).Count -lt 1) { Linea "FALLA: las sondas no producen datos; se aborta antes de drenar"; exit 1 }
Linea "sondas iniciadas (cada ~1 s, desde $cliente)"
Start-Sleep -Seconds $SegundosAntes

# ---------------------------------------------------------------- drenaje
Linea "DRAIN inicio: kubectl drain $Nodo --ignore-daemonsets --delete-emptydir-data"
$drain = Kc drain $Nodo --ignore-daemonsets --delete-emptydir-data --grace-period=30 --timeout=300s
$okDrain = $LASTEXITCODE -eq 0
Volcar "DRAIN fin (exito=$okDrain):" ($drain | Select-String -Pattern 'evicting|evicted|drained|error|cannot' | ForEach-Object { $_.Line })
$nuevaPrimaria = (Kc get pods -n $ns -l "application=spilo,spilo-role=master" -o jsonpath='{.items[0].metadata.name}')
Volcar "tras el drenaje - Patroni (primaria ahora: $nuevaPrimaria):" (Kc exec -n $ns $nuevaPrimaria -c postgres '--' patronictl list)
Volcar "tras el drenaje - pods de aroma-prod por nodo:" (Kc get pods -n $ns -o wide --no-headers | ForEach-Object { ($_ -split '\s+')[0, 1, 2, 6] -join ' ' })
Start-Sleep -Seconds $SegundosDrenado

# --------------------------------------------------------------- uncordon
Linea "UNCORDON: kubectl uncordon $Nodo"
Kc uncordon $Nodo | Out-Null
$limite = (Get-Date).AddMinutes(5)
do { Start-Sleep -Seconds 5; $listas = (Kc get sts aroma-pg -n $ns -o jsonpath='{.status.readyReplicas}') } until ($listas -eq "2" -or (Get-Date) -gt $limite)
Linea "PostgreSQL con $listas instancias listas tras el uncordon"
Start-Sleep -Seconds $SegundosDespues
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
& docker exec $cliente pkill -f "bash -s -- $ip" 2>$null | Out-Null
Volcar "estado final - Patroni:" (Kc exec -n $ns $nuevaPrimaria -c postgres '--' patronictl list)
Volcar "estado final - pods de aroma-prod por nodo:" (Kc get pods -n $ns -o wide --no-headers | ForEach-Object { ($_ -split '\s+')[0, 1, 2, 6] -join ' ' })

# --------------------------------------------------------------- resultado
$filas = @(Get-Content $sondas | Where-Object { $_ -match '^\d{13} (salud|datos) \d{3} ' } | ForEach-Object {
  $p = $_ -split ' '; [pscustomobject]@{ ms = [int64]$p[0]; sonda = $p[1]; codigo = $p[2] } })
foreach ($s in "salud", "datos") {
  $f = @($filas | Where-Object sonda -eq $s)
  $ok = @($f | Where-Object codigo -eq "200").Count
  # mayor ventana de fallo continuo (desde el primer fallo hasta el siguiente exito)
  $max = 0; $ini = $null; $peor = ""
  foreach ($x in $f) {
    if ($x.codigo -ne "200") { if ($null -eq $ini) { $ini = $x.ms } }
    elseif ($null -ne $ini) { $d = ($x.ms - $ini) / 1000; if ($d -gt $max) { $max = $d; $peor = "{0:HH:mm:ss}" -f [DateTimeOffset]::FromUnixTimeMilliseconds($ini).ToLocalTime() }; $ini = $null }
  }
  $pct = if ($f.Count) { [math]::Round(100 * $ok / $f.Count, 2) } else { 0 }
  $codigos = ($f | Group-Object codigo | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join " "
  Linea ("RESULTADO sonda {0}: {1}/{2} respuestas 200 ({3} %) | codigos: {4} | mayor ventana de fallo: {5} s{6}" -f
    $s, $ok, $f.Count, $pct, $codigos, $max, $(if ($peor) { " (desde $peor)" } else { "" }))
}
Linea "FIN prueba de perdida de nodo (detalle por peticion en $(Split-Path -Leaf $sondas))"
