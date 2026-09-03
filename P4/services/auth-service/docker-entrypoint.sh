#!/bin/sh
# Crea la tabla de usuarios y arranca el servicio.
# PostgreSQL puede tardar unos segundos mas que el healthcheck en aceptar
# conexiones de la aplicacion, por eso el script reintenta.
set -e

echo "[auth] preparando la base de datos..."
if [ -f scripts_init_db.py ]; then
  intento=1
  while [ "$intento" -le 10 ]; do
    if python scripts_init_db.py; then
      echo "[auth] tabla de usuarios lista."
      break
    fi
    echo "[auth] la base de datos aun no responde (intento $intento/10). Reintento en 3 s."
    intento=$((intento + 1))
    sleep 3
  done
else
  echo "[auth] no se encontro scripts_init_db.py; se asume que el esquema ya existe."
fi

echo "[auth] arrancando uvicorn en el puerto 8000..."
exec uvicorn app.main:app --host 0.0.0.0 --port 8000
