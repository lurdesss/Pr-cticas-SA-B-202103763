# ============================================================================
# Genera la credencial del usuario "aroma" de PostgreSQL y la deja SELLADA
# en aroma-gitops/bd/credencial.yaml (SealedSecret aroma-pg-app).
#
# - La contrasena se genera al azar (32 caracteres alfanumericos, sin
#   simbolos para poder usarla dentro de una URL de conexion) y solo
#   existe en memoria: se envia por stdin a kubeseal, nunca se escribe en
#   claro ni se imprime.
# - kubeseal cifra con la llave publica del controlador de kube-system;
#   solo ese controlador (o uno restaurado con la misma llave) la descifra.
# - Por defecto NO sobrescribe una credencial existente: cambiarla deja
#   a los datos restaurados con una contrasena distinta. Para rotarla a
#   proposito: -Rotar.
#
# Uso: powershell -ExecutionPolicy Bypass -File P9\scripts\sellar-credencial-bd.ps1
# ============================================================================
param(
  [string]$Contexto = "kind-aroma-p9",
  [string]$Destino  = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) "aroma-gitops\bd\credencial.yaml"),
  [string]$Kubeseal = "kubeseal",
  [switch]$Rotar
)
$ErrorActionPreference = "Stop"

if ((Test-Path $Destino) -and -not $Rotar) {
  Write-Host "Ya existe $Destino; no se sobrescribe (use -Rotar para generar otra)."
  exit 0
}

$alfabeto = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
$bytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$clave = -join ($bytes | ForEach-Object { $alfabeto[$_ % $alfabeto.Length] })
$b64 = { param($t) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($t)) }

$secreto = @{
  apiVersion = "v1"; kind = "Secret"; type = "kubernetes.io/basic-auth"
  metadata = @{
    name = "aroma-pg-app"; namespace = "aroma-prod"
    # Indica a CloudNativePG que recargue la credencial si cambia.
    labels = @{ "cnpg.io/reload" = "true" }
  }
  data = @{ username = (& $b64 "aroma"); password = (& $b64 $clave) }
} | ConvertTo-Json -Depth 5 -Compress
Remove-Variable clave

$sellado = $secreto | & $Kubeseal --context $Contexto `
  --controller-name sealed-secrets-controller --controller-namespace kube-system --format yaml
if ($LASTEXITCODE -ne 0) { throw "kubeseal fallo." }
Remove-Variable secreto

$encabezado = @(
  "# Credencial del usuario aroma de PostgreSQL (Cluster aroma-pg), SELLADA.",
  "# Generada por P9/scripts/sellar-credencial-bd.ps1. Solo texto cifrado:",
  "# la descifra el controlador de Sealed Secrets con la llave respaldada."
)
New-Item -ItemType Directory -Force (Split-Path $Destino) | Out-Null
[IO.File]::WriteAllText($Destino, (($encabezado + $sellado) -join "`n") + "`n")
Write-Host "SealedSecret aroma-pg-app escrito en $Destino"
