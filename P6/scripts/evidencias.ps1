# Recolecta en un solo archivo de texto (para adjuntar como evidencia) la
# salida de los comandos que la rubrica pide poder mostrar: pods, nodos,
# servicios, la IP publica y una peticion real contra ella.
#
#   pwsh -File scripts\evidencias.ps1 -Namespace sa-p6

param(
    [string]$Namespace = "sa-p6"
)

$salida = "evidencia-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"

function Seccion($titulo, $comando) {
    Add-Content -Path $salida -Value "`n=== $titulo ===`n"
    Add-Content -Path $salida -Value "`$ $comando`n"
    Invoke-Expression $comando | Out-String | Add-Content -Path $salida
}

Seccion "Nodos del cluster (requisito: al menos 2)" "kubectl get nodes -o wide"
Seccion "Pods en ejecucion" "kubectl get pods -n $Namespace -o wide"
Seccion "Servicios (el gateway debe mostrar EXTERNAL-IP)" "kubectl get svc -n $Namespace"
Seccion "PersistentVolumeClaims (StorageClass del proveedor)" "kubectl get pvc -n $Namespace"
Seccion "Historial de Helm" "helm history sa-platform -n $Namespace"

$ip = kubectl get svc -n $Namespace sa-platform-gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
if ($ip) {
    Seccion "Peticion real a la IP publica" "curl.exe -s http://$ip/api/salud"
}

Write-Host "Evidencia guardada en $salida" -ForegroundColor Green
