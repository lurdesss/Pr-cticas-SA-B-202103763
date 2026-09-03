#!/usr/bin/env bash
# Recorrido completo del sistema por HTTP. Ejecutar con el stack levantado.
#   bash scripts/prueba-humo.sh
set -uo pipefail

BASE="${BASE:-http://localhost:8080}"
SELLO="$(date +%s)"
COOKIES_ADMIN="$(mktemp)"
COOKIES_CLIENTE="$(mktemp)"
FALLOS=0

azul()  { printf "\n\033[1;36m== %s\033[0m\n" "$1"; }
ok()    { printf "  \033[0;32mOK\033[0m   %s\n" "$1"; }
falla() { printf "  \033[0;31mFALLA\033[0m %s\n" "$1"; FALLOS=$((FALLOS + 1)); }

esperar() {
  local codigo="$1" real="$2" etiqueta="$3"
  if [ "$real" = "$codigo" ]; then ok "$etiqueta ($real)"; else falla "$etiqueta: esperaba $codigo y llego $real"; fi
}

codigo() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

azul "0. El sistema responde"
esperar 200 "$(codigo "$BASE/api/salud")" "GET /api/salud"

azul "1. Registro de una cuenta Admin"
esperar 201 "$(codigo -X POST "$BASE/api/auth/registro" -H 'content-type: application/json' \
  -c "$COOKIES_ADMIN" \
  -d "{\"nombre\":\"Admin Prueba\",\"correo\":\"admin$SELLO@aroma.gt\",\"password\":\"claveSegura123\",\"rol\":\"admin\"}")" \
  "POST /api/auth/registro"

if grep -qi "acceso_token" "$COOKIES_ADMIN"; then ok "la cookie de sesion llego al cliente"; else falla "no se recibio la cookie de sesion"; fi

azul "2. Registro de una cuenta Cliente"
esperar 201 "$(codigo -X POST "$BASE/api/auth/registro" -H 'content-type: application/json' \
  -c "$COOKIES_CLIENTE" \
  -d "{\"nombre\":\"Cliente Prueba\",\"correo\":\"cliente$SELLO@aroma.gt\",\"password\":\"claveSegura123\",\"rol\":\"cliente\"}")" \
  "POST /api/auth/registro"

azul "3. Sin cookie no se pasa del gateway"
esperar 401 "$(codigo -X POST "$BASE/api/catalogo/graphql" -H 'content-type: application/json' \
  -d '{"query":"{ categorias { id } }"}')" "POST /api/catalogo/graphql sin sesion"

azul "4. Catalogo (GraphQL) con las dos cuentas"
esperar 200 "$(codigo -X POST "$BASE/api/catalogo/graphql" -b "$COOKIES_ADMIN" -H 'content-type: application/json' \
  -d '{"query":"{ productos { id nombre precio } }"}')" "Admin consulta el menu"
esperar 200 "$(codigo -X POST "$BASE/api/catalogo/graphql" -b "$COOKIES_CLIENTE" -H 'content-type: application/json' \
  -d '{"query":"{ productos { id nombre precio } }"}')" "Cliente consulta el menu"

azul "5. Inventario (GraphQL): solo Admin"
esperar 200 "$(codigo -X POST "$BASE/api/inventario/graphql" -b "$COOKIES_ADMIN" -H 'content-type: application/json' \
  -d '{"query":"{ insumos { id nombre existencia } }"}')" "Admin consulta bodega"
esperar 403 "$(codigo -X POST "$BASE/api/inventario/graphql" -b "$COOKIES_CLIENTE" -H 'content-type: application/json' \
  -d '{"query":"{ insumos { id nombre } }"}')" "Cliente consulta bodega"

azul "6. Pedidos (REST) con comunicacion directa hacia el catalogo"
PEDIDO="$(curl -s -X POST "$BASE/api/pedidos" -b "$COOKIES_CLIENTE" -H 'content-type: application/json' \
  -d '{"items":[{"productoId":"1","cantidad":2}],"notas":"prueba automatizada"}')"
if echo "$PEDIDO" | grep -q '"total"'; then ok "el Cliente creo un pedido y el total vino del catalogo"; else falla "no se pudo crear el pedido: $PEDIDO"; fi

esperar 200 "$(codigo "$BASE/api/pedidos" -b "$COOKIES_CLIENTE")" "el Cliente lista sus pedidos"

PEDIDO_ID="$(echo "$PEDIDO" | sed -n 's/.*"id":\([0-9]*\).*/\1/p' | head -1)"
if [ -n "$PEDIDO_ID" ]; then
  esperar 200 "$(codigo -X PATCH "$BASE/api/pedidos/$PEDIDO_ID/estado" -b "$COOKIES_ADMIN" \
    -H 'content-type: application/json' -d '{"estado":"preparando"}')" "Admin cambia el estado"
  esperar 403 "$(codigo -X PATCH "$BASE/api/pedidos/$PEDIDO_ID/estado" -b "$COOKIES_CLIENTE" \
    -H 'content-type: application/json' -d '{"estado":"entregado"}')" "Cliente intenta cambiar el estado"
fi

azul "7. Resenas (REST)"
esperar 201 "$(codigo -X POST "$BASE/api/resenas" -b "$COOKIES_CLIENTE" -H 'content-type: application/json' \
  -d '{"producto_id":"1","calificacion":5,"comentario":"El espresso sale parejo."}')" "el Cliente publica una resena"
esperar 409 "$(codigo -X POST "$BASE/api/resenas" -b "$COOKIES_CLIENTE" -H 'content-type: application/json' \
  -d '{"producto_id":"1","calificacion":4,"comentario":"repetida"}')" "la segunda resena del mismo producto"
esperar 422 "$(codigo -X POST "$BASE/api/resenas" -b "$COOKIES_CLIENTE" -H 'content-type: application/json' \
  -d '{"producto_id":"1","calificacion":9,"comentario":"fuera de rango"}')" "calificacion fuera de 1..5"
esperar 200 "$(codigo "$BASE/api/resenas/resumen/1" -b "$COOKIES_ADMIN")" "resumen de calificaciones"

azul "8. Diagnostico de permisos del rol"
curl -s "$BASE/api/diagnostico" -b "$COOKIES_CLIENTE" | head -c 400; echo

rm -f "$COOKIES_ADMIN" "$COOKIES_CLIENTE"

azul "Resultado"
if [ "$FALLOS" -eq 0 ]; then
  printf "  \033[0;32mTodas las comprobaciones pasaron.\033[0m\n"
else
  printf "  \033[0;31m%s comprobacion(es) fallaron.\033[0m\n" "$FALLOS"
  exit 1
fi
