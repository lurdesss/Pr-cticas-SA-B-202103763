# Guardar como P4\scripts\diagnostico.ps1 y ejecutar desde P4:
#   pwsh -ExecutionPolicy Bypass -File scripts\diagnostico.ps1
#
# Identifica por que el gateway no alcanza al microservicio de autorizacion.

function Titulo($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Bien($t)   { Write-Host "  OK    $t" -ForegroundColor Green }
function Mal($t)    { Write-Host "  FALLA $t" -ForegroundColor Red }
function Nota($t)   { Write-Host "  ...   $t" -ForegroundColor DarkGray }

Titulo "1. Estado de los contenedores"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

Titulo "2. Que dice /api/salud"
try {
  $r = Invoke-WebRequest -Uri "http://localhost:8080/api/salud" -SkipHttpErrorCheck
  $salud = $r.Content | ConvertFrom-Json
  foreach ($d in $salud.dependencias) {
    $linea = "{0,-20} {1,-10} codigo={2} {3}ms {4}" -f $d.servicio, $d.estado, $d.codigo, $d.ms, $d.detalle
    if ($d.estado -eq "arriba") { Bien $linea } else { Mal $linea }
  }
} catch { Mal "el gateway no respondio: $($_.Exception.Message)" }

Titulo "3. authz-service visto desde el host (puerto 8082)"
foreach ($ruta in @("/openapi.json", "/autorizacion/politicas")) {
  try {
    $r = Invoke-WebRequest -Uri "http://localhost:8082$ruta" -SkipHttpErrorCheck -TimeoutSec 5
    if ($r.StatusCode -eq 200) { Bien "GET $ruta (200)" } else { Mal "GET $ruta ($($r.StatusCode))" }
    if ($ruta -eq "/autorizacion/politicas" -and $r.StatusCode -eq 200) { Nota $r.Content }
  } catch { Mal "GET $ruta -> $($_.Exception.Message)" }
}

Titulo "4. POST /autorizacion/verificar directo (sin gateway)"
foreach ($caso in @(
    @{ rol = "admin";   permiso = "catalogo:usar" },
    @{ rol = "cliente"; permiso = "catalogo:usar" },
    @{ rol = "admin";   permiso = "inventario:gestionar" },
    @{ rol = "cliente"; permiso = "inventario:gestionar" },
    @{ rol = "admin";   permiso = "ruta1:leer" }
)) {
  try {
    $r = Invoke-WebRequest -Uri "http://localhost:8082/autorizacion/verificar" -Method POST `
         -ContentType "application/json" -Body ($caso | ConvertTo-Json -Compress) `
         -SkipHttpErrorCheck -TimeoutSec 5
    $etiqueta = "$($caso.rol) / $($caso.permiso) -> $($r.StatusCode) $($r.Content)"
    if ($r.StatusCode -eq 200) { Bien $etiqueta } else { Mal $etiqueta }
  } catch { Mal "$($caso.rol) / $($caso.permiso) -> $($_.Exception.Message)" }
}

Titulo "5. authz-service visto DESDE EL GATEWAY (red interna)"
docker compose exec -T gateway node -e "
const probar = async (url) => {
  try { const r = await fetch(url, { signal: AbortSignal.timeout(4000) }); console.log('  OK   ', url, '->', r.status); }
  catch (e) { console.log('  FALLA', url, '->', e.cause?.code ?? e.name ?? e.message); }
};
(async () => {
  await probar('http://authz-service:8001/openapi.json');
  await probar('http://authz-service:8000/openapi.json');
  await probar('http://auth-service:8000/openapi.json');
  try {
    const r = await fetch('http://authz-service:8001/autorizacion/verificar', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ rol: 'admin', permiso: 'catalogo:usar' }),
      signal: AbortSignal.timeout(4000),
    });
    console.log('  verificar ->', r.status, await r.text());
  } catch (e) { console.log('  verificar -> FALLA', e.cause?.code ?? e.name ?? e.message); }
})();
"

Titulo "6. Ultimas 40 lineas del log de authz-service"
docker compose logs --tail=40 authz-service

Titulo "7. Ultimas 25 lineas del log del gateway"
docker compose logs --tail=25 gateway

Titulo "8. Que hay dentro del contenedor de authz-service"
docker compose exec -T authz-service sh -c "ls -la /app && echo '--- app/ ---' && ls -la /app/app"

Write-Host "`nListo. Lo importante esta en los bloques 5, 6 y 8." -ForegroundColor Yellow
