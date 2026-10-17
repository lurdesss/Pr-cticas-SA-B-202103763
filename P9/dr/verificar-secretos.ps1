# ============================================================================
# Verifica la continuidad de los secretos (criterio 2.4) despues de una
# reconstruccion, SIN mostrar ningun valor secreto:
#
#   1. La llave de Sealed Secrets del cluster es la MISMA que la copia
#      cifrada de respaldo (DPAPI): se compara la huella sha256 del
#      certificado publico (tls.crt). La llave privada nunca se imprime.
#   2. El controlador registro esa llave al arrancar (no genero una nueva).
#   3. Los SealedSecrets de aroma-gitops se descifraron (condicion Synced).
#   4. El Secret resultante existe con sus claves (solo nombres).
#   5. Prueba funcional: Velero usa esa credencial y su destino (MinIO)
#      esta Available.
#
# Uso:  powershell -ExecutionPolicy Bypass -File P9\dr\verificar-secretos.ps1 [-Registro <archivo>]
# Codigo de salida 0 si las 5 comprobaciones pasan, 1 si alguna falla.
# ============================================================================
param(
  [string]$Contexto = "kind-aroma-p9",
  [string]$Copia    = (Join-Path $env:USERPROFILE ".aroma-p9\sealed-secrets-llave.dpapi"),
  [string]$Registro = ""
)
$ErrorActionPreference = "Continue"
Add-Type -AssemblyName System.Security
$fallas = 0

function Linea([string]$t) {
  $l = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"), $t
  Write-Host $l
  if ($Registro) { Add-Content -Path $Registro -Value $l -Encoding utf8 }
}
function Resultado([bool]$ok, [string]$t) {
  if ($ok) { Linea "OK     $t" } else { Linea "FALLA  $t"; $script:fallas++ }
}
function Huella([string]$b64) {
  $sha = [Security.Cryptography.SHA256]::Create()
  ($sha.ComputeHash([Convert]::FromBase64String($b64)) | ForEach-Object { $_.ToString("x2") }) -join ""
}
function Kj([string[]]$a) { (& kubectl --context $Contexto @a 2>$null | Out-String) | ConvertFrom-Json }

Linea "Verificacion de continuidad de secretos (contexto $Contexto)"

# 1. llave del cluster == copia de respaldo (por huella del certificado publico)
$vivas = @((Kj @("get", "secret", "-n", "kube-system", "-l", "sealedsecrets.bitnami.com/sealed-secrets-key", "-o", "json")).items)
$huellasVivas = @($vivas | ForEach-Object { Huella $_.data.'tls.crt' })
if (Test-Path $Copia) {
  $json = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect(
    [IO.File]::ReadAllBytes($Copia), $null, [Security.Cryptography.DataProtectionScope]::CurrentUser))
  $huellasCopia = @(($json | ConvertFrom-Json).items | ForEach-Object { Huella $_.data.'tls.crt' })
  Remove-Variable json
  $comun = @($huellasCopia | Where-Object { $huellasVivas -contains $_ })
  Resultado ($comun.Count -ge 1) ("llave del cluster = copia de respaldo (huella cert " +
    ($(if ($comun.Count) { $comun[0].Substring(0, 16) } else { "sin coincidencia" })) +
    "...; llaves en cluster: $($vivas.Count), en copia: $($huellasCopia.Count))")
} else {
  Resultado $false "no existe la copia cifrada de la llave ($Copia)"
}

# 2. el controlador registro una llave existente (no genero una nueva)
$log = & kubectl --context $Contexto logs -n kube-system deploy/sealed-secrets-controller 2>$null | Out-String
# (Ojo: PowerShell no distingue mayusculas en variables; no usar un nombre
# que choque con el parametro -Registro.)
$llavesLog = [regex]::Matches($log, 'registered private key"? secretname=(\S+)') | ForEach-Object { $_.Groups[1].Value }
$nueva = $log -match 'New key written|Generating new key|creating new key'
Resultado (@($llavesLog).Count -ge 1 -and -not $nueva) ("controlador registro la llave existente: " +
  (@($llavesLog) -join ", ") + $(if ($nueva) { " (AVISO: el log indica que genero una llave nueva)" } else { "" }))

# 3. todos los SealedSecrets descifrados
$ss = @((Kj @("get", "sealedsecrets", "-A", "-o", "json")).items)
foreach ($s in $ss) {
  $c = @($s.status.conditions | Where-Object { $_.type -eq "Synced" })[0]
  Resultado ($c.status -eq "True") "SealedSecret $($s.metadata.namespace)/$($s.metadata.name) descifrado (Synced=$($c.status))"
}
if ($ss.Count -eq 0) { Resultado $false "no hay SealedSecrets en el cluster" }

# 4. el Secret resultante existe (solo nombres de claves)
$sec = Kj @("get", "secret", "velero-minio-credentials", "-n", "velero", "-o", "json")
$claves = if ($sec) { @($sec.data.PSObject.Properties.Name) } else { @() }
Resultado ($claves -contains "cloud") "Secret velero/velero-minio-credentials existe (claves: $($claves -join ', '))"

# 5. prueba funcional: Velero se autentica en MinIO con esa credencial
$bsl = Kj @("get", "backupstoragelocations.velero.io", "default", "-n", "velero", "-o", "json")
Resultado ($bsl.status.phase -eq "Available") "Velero autentica en MinIO con la credencial descifrada (BSL default: $($bsl.status.phase))"

Linea ("Resultado: " + $(if ($fallas -eq 0) { "continuidad de secretos VERIFICADA" } else { "$fallas comprobacion(es) fallida(s)" }))
exit [int]($fallas -gt 0)
