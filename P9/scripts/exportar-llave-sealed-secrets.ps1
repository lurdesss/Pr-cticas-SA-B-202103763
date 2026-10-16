# ============================================================================
# Exporta las llaves privadas de Sealed Secrets del cluster a un archivo
# CIFRADO fuera del repositorio (respaldo de la llave, copia principal).
#
# Por que existe: Velero no puede ser la fuente de la llave al
# reconstruir, porque Velero necesita las credenciales de MinIO, que son
# un SealedSecret descifrable solo con esa misma llave. Esta copia rompe
# ese ciclo: P9/terraform/bootstrap.tf la vuelve a cargar en kube-system
# ANTES de instalar ArgoCD y el controlador.
#
# Cifrado: DPAPI de Windows (ambito CurrentUser). Solo esta cuenta de
# Windows en esta maquina puede descifrar el archivo. La llave nunca se
# escribe en claro en disco ni se imprime en pantalla.
# Limite: si se pierde esta maquina o esta cuenta, la copia es ilegible;
# la copia secundaria es el Schedule "respaldo-llaves" de Velero en MinIO.
#
# Uso:  powershell -ExecutionPolicy Bypass -File P9\scripts\exportar-llave-sealed-secrets.ps1
# ============================================================================
param(
  [string]$Contexto = "kind-aroma-p9",
  [string]$Destino  = (Join-Path $env:USERPROFILE ".aroma-p9\sealed-secrets-llave.dpapi")
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Security

$json = kubectl --context $Contexto get secret -n kube-system `
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o json
if ($LASTEXITCODE -ne 0) { throw "No se pudieron leer las llaves del cluster ($Contexto)." }

$lista = $json | ConvertFrom-Json
if ($lista.items.Count -lt 1) { throw "El cluster no tiene llaves de Sealed Secrets." }

# Se quitan los campos que el servidor asigna (uid, resourceVersion...):
# con ellos, "kubectl apply" falla al crear el objeto en un cluster nuevo.
foreach ($s in $lista.items) {
  foreach ($campo in "uid", "resourceVersion", "creationTimestamp", "managedFields", "ownerReferences") {
    $s.metadata.PSObject.Properties.Remove($campo)
  }
  if ($s.metadata.annotations) {
    $s.metadata.annotations.PSObject.Properties.Remove("kubectl.kubernetes.io/last-applied-configuration")
  }
}
$lista.PSObject.Properties.Remove("metadata")

$bytes   = [Text.Encoding]::UTF8.GetBytes(($lista | ConvertTo-Json -Depth 20 -Compress))
$cifrado = [Security.Cryptography.ProtectedData]::Protect(
  $bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)

New-Item -ItemType Directory -Force (Split-Path $Destino) | Out-Null
[IO.File]::WriteAllBytes($Destino, $cifrado)

$hash = (Get-FileHash $Destino -Algorithm SHA256).Hash.Substring(0, 16)
Write-Host "Llaves exportadas: $($lista.items.Count) (nombres: $(($lista.items | ForEach-Object { $_.metadata.name }) -join ', '))"
Write-Host "Archivo cifrado (DPAPI): $Destino  sha256=$hash..."
