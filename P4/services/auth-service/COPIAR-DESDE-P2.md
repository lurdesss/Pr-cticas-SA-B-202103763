# Como poblar esta carpeta

Esta carpeta contiene el **servicio de autenticacion de la Practica 2**. El
codigo no se reescribe: se copia tal cual, y esta carpeta solo agrega el
`Dockerfile` y el `docker-entrypoint.sh` que ya estan aqui.

## 1. Copiar el codigo

Desde la raiz del repositorio (`Practicas-SA-B-202103763`):

**Windows PowerShell**

```powershell
Copy-Item -Path "P2\backend\app"                -Destination "P4\services\auth-service\"  -Recurse -Force
Copy-Item -Path "P2\backend\requirements.txt"   -Destination "P4\services\auth-service\"  -Force
Copy-Item -Path "P2\backend\scripts_init_db.py" -Destination "P4\services\auth-service\"  -Force
Copy-Item -Path "P2\backend\.env.example"       -Destination "P4\services\auth-service\"  -Force
```

**Linux / macOS**

```bash
cp -r P2/backend/app                P4/services/auth-service/
cp    P2/backend/requirements.txt   P4/services/auth-service/
cp    P2/backend/scripts_init_db.py P4/services/auth-service/
cp    P2/backend/.env.example       P4/services/auth-service/
```

No copies `.venv/`, `.env` ni `.pytest_cache/`. El `.dockerignore` de esta
carpeta ya los excluye de la imagen, pero tampoco tiene sentido versionarlos.

Al terminar, la carpeta debe verse asi:

```text
services/auth-service/
├── app/                    <- copiado de P2
├── requirements.txt        <- copiado de P2
├── scripts_init_db.py      <- copiado de P2
├── .env.example            <- copiado de P2 (referencia)
├── Dockerfile              <- de la Practica 4
├── docker-entrypoint.sh    <- de la Practica 4
└── .dockerignore           <- de la Practica 4
```

## 2. Verificar el nombre de la variable del microservicio de autorizacion

Abre `.env.example` (el que acabas de copiar) y busca la variable que
guarda la URL del microservicio de autorizacion. En
`P4/docker-compose.yml`, el servicio `auth-service` envia cuatro nombres
posibles apuntando todos a `http://authz-service:8001`:

```yaml
AUTHZ_URL: "http://authz-service:8001"
AUTHZ_SERVICE_URL: "http://authz-service:8001"
AUTORIZACION_URL: "http://authz-service:8001"
SERVICIO_AUTORIZACION_URL: "http://authz-service:8001"
```

Deja **solo la que existe realmente** en tu configuracion y borra las otras
tres. Si tu variable se llama de otra forma, agregala con ese nombre.

## 3. Nada mas

Los secretos, la cadena de conexion y los tiempos del token los inyecta
`docker-compose.yml` desde `P4/.env`. Dentro del contenedor no hace falta
ningun archivo `.env`.
