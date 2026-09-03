# Recorrido completo del sistema por HTTP. Ejecutar con el stack levantado.
#   powershell -ExecutionPolicy Bypass -File scripts\prueba-humo.ps1

$Base = if ($env:BASE) { $env:BASE } else { "http://localhost:8080" }
$Sello = [int][double]::Parse((Get-Date -UFormat %s))
$Fallos = 0

function Titulo($texto) { Write-Host "`n== $texto" -ForegroundColor Cyan }
function Ok($texto)     { Write-Host "  OK    $texto" -ForegroundColor Green }
function Falla($texto)  { Write-Host "  FALLA $texto" -ForegroundColor Red; $script:Fallos++ }

function Llamar($Metodo, $Ruta, $Cuerpo, $Sesion) {
  $parametros = @{
    Uri                = "$Base$Ruta"
    Method             = $Metodo
    WebSession         = $Sesion
    SkipHttpErrorCheck = $true
    ContentType        = "application/json"
  }
  if ($Cuerpo) { $parametros.Body = ($Cuerpo | ConvertTo-Json -Depth 6 -Compress) }
  return Invoke-WebRequest @parametros
}

function Esperar($Codigo, $Respuesta, $Etiqueta) {
  if ($Respuesta.StatusCode -eq $Codigo) { Ok "$Etiqueta ($Codigo)" }
  else { Falla "$Etiqueta`: esperaba $Codigo y llego $($Respuesta.StatusCode)" }
}

$admin   = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$cliente = New-Object Microsoft.PowerShell.Commands.WebRequestSession

Titulo "0. El sistema responde"
Esperar 200 (Llamar GET "/api/salud" $null $admin) "GET /api/salud"

Titulo "1. Registro de una cuenta Admin"
$r = Llamar POST "/api/auth/registro" @{ nombre="Admin Prueba"; correo="admin$Sello@aroma.gt"; password="claveSegura123"; rol="admin" } $admin
Esperar 201 $r "POST /api/auth/registro"

Titulo "2. Registro de una cuenta Cliente"
$r = Llamar POST "/api/auth/registro" @{ nombre="Cliente Prueba"; correo="cliente$Sello@aroma.gt"; password="claveSegura123"; rol="cliente" } $cliente
Esperar 201 $r "POST /api/auth/registro"

Titulo "3. Sin cookie no se pasa del gateway"
$anonimo = New-Object Microsoft.PowerShell.Commands.WebRequestSession
Esperar 401 (Llamar POST "/api/catalogo/graphql" @{ query="{ categorias { id } }" } $anonimo) "catalogo sin sesion"

Titulo "4. Catalogo (GraphQL)"
Esperar 200 (Llamar POST "/api/catalogo/graphql" @{ query="{ productos { id nombre precio } }" } $admin)   "Admin consulta el menu"
Esperar 200 (Llamar POST "/api/catalogo/graphql" @{ query="{ productos { id nombre precio } }" } $cliente) "Cliente consulta el menu"

Titulo "5. Inventario (GraphQL): solo Admin"
Esperar 200 (Llamar POST "/api/inventario/graphql" @{ query="{ insumos { id nombre existencia } }" } $admin)   "Admin consulta bodega"
Esperar 403 (Llamar POST "/api/inventario/graphql" @{ query="{ insumos { id nombre } }" } $cliente) "Cliente consulta bodega"

Titulo "6. Pedidos (REST)"
$r = Llamar POST "/api/pedidos" @{ items=@(@{ productoId="1"; cantidad=2 }); notas="prueba automatizada" } $cliente
Esperar 201 $r "el Cliente crea un pedido"
$pedidoId = ($r.Content | ConvertFrom-Json).id
Esperar 200 (Llamar GET "/api/pedidos" $null $cliente) "el Cliente lista sus pedidos"
Esperar 200 (Llamar PATCH "/api/pedidos/$pedidoId/estado" @{ estado="preparando" } $admin)   "Admin cambia el estado"
Esperar 403 (Llamar PATCH "/api/pedidos/$pedidoId/estado" @{ estado="entregado" } $cliente) "Cliente intenta cambiar el estado"

Titulo "7. Resenas (REST)"
Esperar 201 (Llamar POST "/api/resenas" @{ producto_id="1"; calificacion=5; comentario="El espresso sale parejo." } $cliente) "el Cliente publica una resena"
Esperar 409 (Llamar POST "/api/resenas" @{ producto_id="1"; calificacion=4; comentario="repetida" } $cliente) "la segunda resena del mismo producto"
Esperar 422 (Llamar POST "/api/resenas" @{ producto_id="1"; calificacion=9; comentario="fuera de rango" } $cliente) "calificacion fuera de 1..5"
Esperar 200 (Llamar GET "/api/resenas/resumen/1" $null $admin) "resumen de calificaciones"

Titulo "8. Diagnostico de permisos del rol Cliente"
(Llamar GET "/api/diagnostico" $null $cliente).Content

Titulo "Resultado"
if ($Fallos -eq 0) { Write-Host "  Todas las comprobaciones pasaron." -ForegroundColor Green }
else { Write-Host "  $Fallos comprobacion(es) fallaron." -ForegroundColor Red; exit 1 }
