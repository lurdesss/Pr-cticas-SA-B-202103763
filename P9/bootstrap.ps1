# ============================================================================
# P9/bootstrap.ps1 - punto de entrada unico del bootstrap de dia cero.
#
#   powershell -ExecutionPolicy Bypass -File P9\bootstrap.ps1
#
# Un solo comando reconstruye el entorno completo, sin pasos intermedios:
#   1. Verifica herramientas, Docker y MinIO (almacen de Velero, fuera
#      del cluster).
#   2. terraform init contra el backend remoto (HCP Terraform, con lock).
#   3. Si el cluster ya no existe pero el estado remoto lo sigue
#      describiendo (perdida total del cluster), limpia esas entradas
#      del estado para que Terraform las vuelva a crear.
#   4. terraform apply del cluster kind (3 nodos).
#   5. Conecta MinIO a la red "kind" (Velero lo resuelve como minio:9000).
#   6. terraform apply completo: llave de Sealed Secrets -> ArgoCD ->
#      Application raiz aroma-root.
#   7. Espera a que aroma-root y sus Applications hijas esten
#      Synced/Healthy (ArgoCD despliega el resto desde aroma-gitops).
#
# Cada paso deja marcas de tiempo en P9/evidencias/bootstrap-<fecha>.log;
# la diferencia entre la primera y la ultima marca es el RTO de la
# reconstruccion.
# ============================================================================
param(
  # Solo para el primer despliegue de la historia del sistema (sin llave
  # previa de Sealed Secrets que conservar).
  [switch]$PermitirLlaveNueva,
  [int]$EsperaMinutos = 25
)

$ErrorActionPreference = "Continue"
$p9       = Split-Path -Parent $MyInvocation.MyCommand.Path
$tf       = Join-Path $p9 "terraform"
$cluster  = "aroma-p9"
$contexto = "kind-$cluster"
$appRaiz  = "aroma-root"
New-Item -ItemType Directory -Force (Join-Path $p9 "evidencias") | Out-Null
$registro = Join-Path $p9 ("evidencias\bootstrap-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

# El backend "remote" apunta a un unico workspace de HCP; Terraform lo
# expone localmente como "default".
$env:TF_WORKSPACE = "default"
$varsTf = @("-input=false", "-lock-timeout=120s")
if ($PermitirLlaveNueva) { $varsTf += "-var=permitir_llave_nueva=true" }

function Marca([string]$texto) {
  $linea = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff zzz"), $texto
  Write-Host $linea -ForegroundColor Cyan
  Add-Content -Path $registro -Value $linea -Encoding utf8
}
function Registrar {
  process { $l = "$_"; Write-Host $l; Add-Content -Path $registro -Value $l -Encoding utf8 }
}
function Detener([string]$texto) {
  Marca "FALLA: $texto"
  Marca "Bootstrap detenido. Registro: $registro"
  exit 1
}

$inicio = Get-Date
Marca "INICIO bootstrap P9 (cluster $cluster)"

# ------------------------------------------------------------ 1. requisitos
Marca "PASO 1 verificar herramientas, Docker y MinIO"
foreach ($h in "docker", "kind", "terraform", "kubectl", "helm") {
  if (-not (Get-Command $h -ErrorAction SilentlyContinue)) { Detener "falta la herramienta '$h' en el PATH" }
}
docker info --format "{{.ServerVersion}}" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Detener "Docker Desktop no esta en ejecucion" }
$minio = docker inspect -f "{{.State.Running}}" minio 2>$null
if ($LASTEXITCODE -ne 0) { Detener "no existe el contenedor 'minio' (almacen externo de Velero)" }
if ($minio -ne "true") {
  docker start minio 2>&1 | Registrar
  if ($LASTEXITCODE -ne 0) { Detener "no se pudo iniciar el contenedor minio" }
}
helm version --short 2>&1 | Registrar
Marca "FIN PASO 1"

# --------------------------------------------------------- 2. terraform init
Marca "PASO 2 terraform init (backend remoto HCP Terraform)"
terraform "-chdir=$tf" init -input=false -no-color 2>&1 | Registrar
if ($LASTEXITCODE -ne 0) { Detener "terraform init" }
Marca "FIN PASO 2"

# --------------------------------------------- 3. estado de un cluster perdido
Marca "PASO 3 comparar estado remoto con el cluster real"
$existe   = kind get clusters 2>$null | Where-Object { $_ -eq $cluster }
$enEstado = @(terraform "-chdir=$tf" state list 2>$null)
if (-not $existe -and $enEstado.Count -gt 0) {
  # El estado describe recursos de un cluster que ya no existe. Sin esta
  # limpieza, el plan intentaria leerlos de una API que no responde.
  Marca "El cluster no existe y el estado tiene $($enEstado.Count) recursos: se limpian del estado"
  terraform "-chdir=$tf" state rm -lock-timeout=120s @enEstado 2>&1 | Registrar
  if ($LASTEXITCODE -ne 0) { Detener "terraform state rm" }
} else {
  Marca "Estado coherente (cluster existe: $([bool]$existe); recursos en estado: $($enEstado.Count))"
}
Marca "FIN PASO 3"

# ---------------------------------------------------------- 4. cluster kind
# Primero solo el cluster: los providers kubernetes y helm necesitan que
# el contexto kind-aroma-p9 exista en ~/.kube/config para planificar.
Marca "PASO 4 terraform apply del cluster kind (1 control-plane + 2 workers)"
terraform "-chdir=$tf" apply -auto-approve -no-color @varsTf "-target=null_resource.cluster_kind" 2>&1 | Registrar
if ($LASTEXITCODE -ne 0) { Detener "terraform apply del cluster" }
kubectl --context $contexto get nodes -o wide 2>&1 | Registrar
Marca "FIN PASO 4"

# ------------------------------------------------- 5. MinIO en la red kind
Marca "PASO 5 conectar MinIO a la red kind"
$enRed = docker network inspect kind -f "{{range .Containers}}{{.Name}} {{end}}" 2>$null
if (($enRed -split " ") -notcontains "minio") {
  docker network connect kind minio 2>&1 | Registrar
  if ($LASTEXITCODE -ne 0) { Detener "no se pudo conectar minio a la red kind" }
}
Marca "FIN PASO 5"

# ---------------------------------- 6. llave -> ArgoCD -> Application raiz
Marca "PASO 6 terraform apply completo (llave Sealed Secrets, ArgoCD, $appRaiz)"
terraform "-chdir=$tf" apply -auto-approve -no-color @varsTf 2>&1 | Registrar
if ($LASTEXITCODE -ne 0) { Detener "terraform apply completo" }
Marca "FIN PASO 6"

# ------------------------------------------- 7. esperar la sincronizacion
Marca "PASO 7 esperar $appRaiz y sus Applications hijas Synced/Healthy (max $EsperaMinutos min)"
$limite = (Get-Date).AddMinutes($EsperaMinutos)
$listo  = $false
$ultimo = ""
while ((Get-Date) -lt $limite) {
  $json = kubectl --context $contexto get applications -n argocd -o json 2>$null
  if ($LASTEXITCODE -eq 0 -and $json) {
    $apps = @((($json | Out-String) | ConvertFrom-Json).items)
    $raiz = $apps | Where-Object { $_.metadata.name -eq $appRaiz }
    $hijas = @($apps | Where-Object { $_.metadata.name -ne $appRaiz })
    $pend = @($apps | Where-Object { $_.status.sync.status -ne "Synced" -or $_.status.health.status -ne "Healthy" })
    $resumen = ($apps | ForEach-Object { "$($_.metadata.name)=$($_.status.sync.status)/$($_.status.health.status)" }) -join " "
    if ($resumen -ne $ultimo) { Marca "estado: $resumen"; $ultimo = $resumen }
    if ($raiz -and $hijas.Count -ge 2 -and $pend.Count -eq 0) { $listo = $true; break }
  }
  Start-Sleep -Seconds 15
}
if (-not $listo) { Detener "las Applications no llegaron a Synced/Healthy en $EsperaMinutos min" }
Marca "FIN PASO 7"

# ----------------------------------------------------------------- resumen
kubectl --context $contexto get nodes 2>&1 | Registrar
kubectl --context $contexto get applications -n argocd 2>&1 | Registrar
kubectl --context $contexto get backupstoragelocations -n velero 2>&1 | Registrar
$duracion = (Get-Date) - $inicio
Marca ("FIN bootstrap P9: duracion {0:hh\:mm\:ss} ({1:N0} s)" -f $duracion, $duracion.TotalSeconds)
Marca "Registro: $registro"
