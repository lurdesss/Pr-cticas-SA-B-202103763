# ============================================================================
# Restaura en kube-system las llaves de Sealed Secrets desde la copia
# cifrada (DPAPI) que genera exportar-llave-sealed-secrets.ps1.
#
# Lo invoca Terraform (null_resource.llave_sealed_secrets en
# P9/terraform/bootstrap.tf) justo despues de crear el cluster y ANTES de
# instalar ArgoCD: cuando el controlador arranque (ola -2 de aroma-root)
# encuentra la llave y no genera una nueva, asi los SealedSecrets que ya
# estan en aroma-gitops se siguen descifrando.
#
# La llave se descifra en memoria y se envia por stdin a kubectl: no se
# escribe en claro en disco ni se imprime.
# ============================================================================
param(
  [string]$Contexto = "kind-aroma-p9",
  [string]$Origen   = (Join-Path $env:USERPROFILE ".aroma-p9\sealed-secrets-llave.dpapi"),
  # Solo para el primer despliegue de la historia del sistema, cuando
  # aun no existe ninguna llave que conservar.
  [switch]$PermitirLlaveNueva
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Security

if (-not (Test-Path $Origen)) {
  if ($PermitirLlaveNueva) {
    Write-Host "Sin copia de la llave en $Origen; el controlador generara una llave nueva."
    exit 0
  }
  Write-Error ("No existe la copia de la llave ($Origen). Sin ella los SealedSecrets " +
    "de aroma-gitops no se podran descifrar. Restaure la copia o ejecute el " +
    "bootstrap con -PermitirLlaveNueva y vuelva a sellar los secretos.")
  exit 1
}

$bytes = [Security.Cryptography.ProtectedData]::Unprotect(
  [IO.File]::ReadAllBytes($Origen), $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
$json  = [Text.Encoding]::UTF8.GetString($bytes)

$salida = $json | kubectl --context $Contexto apply -n kube-system -f - 2>&1
if ($LASTEXITCODE -ne 0) { Write-Error "kubectl no pudo cargar la llave: $salida"; exit 1 }
# Solo se muestran los nombres de los objetos creados, nunca su contenido.
$salida | ForEach-Object { Write-Host "  $_" }
Write-Host "Llave de Sealed Secrets restaurada en kube-system."
