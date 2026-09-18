# Construye las 6 imagenes propias de Aroma y las publica en DOCR
# (DigitalOcean Container Registry).
#
#   pwsh -File scripts\construir-y-publicar.ps1 -Registro "aroma"
#
# Debe correrse desde la carpeta P6, con P5 como carpeta hermana
# (..\P5\services debe existir), y con "doctl registry login" ya hecho.
#
# Nota sobre el plan "basic" de DOCR: incluye 5 GB de almacenamiento
# PERO TAMBIEN un limite de 5 repositorios (no de imagenes ni de
# espacio). Con 6 servicios propios, uno de ellos tiene que compartir el
# nombre de repositorio con otro y distinguirse solo por la etiqueta
# (tag): el limite de DOCR es por nombre de repositorio, no por cuantas
# etiquetas tenga adentro. Aqui "cronjob-resumen" se publica DENTRO del
# repositorio "pedidos-service" (con quien comparte base de datos y
# logica de negocio), bajo la etiqueta "cronjob-resumen-<version>" en vez
# de crear un sexto repositorio.

param(
    [Parameter(Mandatory=$true)][string]$Registro,
    [string]$Tag = "1.0.0"
)

$ErrorActionPreference = "Stop"
$registroCompleto = "registry.digitalocean.com/$Registro"

Write-Host "`n== Construyendo imagenes con el Docker local ==" -ForegroundColor Cyan

$servicios = @(
    @{ nombre = "gateway";              ruta = "..\P5\services\gateway";            repo = "gateway";            tag = $Tag },
    @{ nombre = "catalogo-service";     ruta = "..\P5\services\catalogo-service";    repo = "catalogo-service";   tag = $Tag },
    @{ nombre = "inventario-service";   ruta = "..\P5\services\inventario-service";  repo = "inventario-service"; tag = $Tag },
    @{ nombre = "pedidos-service";      ruta = "..\P5\services\pedidos-service";     repo = "pedidos-service";    tag = $Tag },
    @{ nombre = "resenas-service";      ruta = "..\P5\services\resenas-service";     repo = "resenas-service";    tag = $Tag },
    # Comparte repositorio con pedidos-service (ver nota arriba): no crea
    # un sexto nombre de repositorio, solo una etiqueta distinta.
    @{ nombre = "cronjob-resumen";      ruta = "..\P5\scripts\cronjob-resumen";      repo = "pedidos-service";    tag = "cronjob-resumen-$Tag" }
)

foreach ($s in $servicios) {
    $imagen = "$registroCompleto/$($s.repo):$($s.tag)"
    Write-Host "`n-- $($s.nombre) --" -ForegroundColor Yellow
    docker build -t $imagen $s.ruta
    if ($LASTEXITCODE -ne 0) { throw "Fallo el build de $($s.nombre)" }

    Write-Host "Publicando $imagen ..."
    docker push $imagen
    if ($LASTEXITCODE -ne 0) { throw "Fallo el push de $($s.nombre)" }
}

Write-Host "`n== Listo. Verifica con: ==" -ForegroundColor Green
Write-Host "doctl registry repository list-v2 $Registro"
Write-Host "(deben aparecer 5 repositorios, no 6: cronjob-resumen vive como etiqueta dentro de pedidos-service)"
