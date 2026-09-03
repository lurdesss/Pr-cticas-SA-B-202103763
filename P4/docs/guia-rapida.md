# Guia rapida — levantar, usar y probar

Documento operativo. Si solo tienes diez minutos antes de calificar, esto es
lo que necesitas.

---

## Parte 1 — Levantar (15 minutos la primera vez)

### Paso 1. Colocar la carpeta

`P4` va en la raiz del repositorio, junto a `P1`, `P2` y `P3`:

```text
Practicas-SA-B-202103763/
├── P1/
├── P2/
├── P3/
└── P4/
```

### Paso 2. Traer los dos servicios de la Practica 2

Desde la raiz del repositorio:

**Windows PowerShell**

```powershell
Copy-Item -Path "P2\backend\app"                -Destination "P4\services\auth-service\"  -Recurse -Force
Copy-Item -Path "P2\backend\requirements.txt"   -Destination "P4\services\auth-service\"  -Force
Copy-Item -Path "P2\backend\scripts_init_db.py" -Destination "P4\services\auth-service\"  -Force
Copy-Item -Path "P2\backend\.env.example"       -Destination "P4\services\auth-service\"  -Force

Copy-Item -Path "P2\authz-service\app"              -Destination "P4\services\authz-service\" -Recurse -Force
Copy-Item -Path "P2\authz-service\requirements.txt" -Destination "P4\services\authz-service\" -Force
```

**Linux / macOS**

```bash
cp -r P2/backend/app                P4/services/auth-service/
cp    P2/backend/requirements.txt   P4/services/auth-service/
cp    P2/backend/scripts_init_db.py P4/services/auth-service/
cp    P2/backend/.env.example       P4/services/auth-service/

cp -r P2/authz-service/app              P4/services/authz-service/
cp    P2/authz-service/requirements.txt P4/services/authz-service/
```

No copies `.venv/`, `.env` ni `.pytest_cache/`.

### Paso 3. Agregar los permisos de la Practica 4

Abre `P4/services/authz-service/app/politicas.py` y **agrega** (sin borrar
los de P2):

```python
"admin": {
    "ruta1:leer", "ruta2:leer",
    "catalogo:usar", "inventario:gestionar",
    "pedidos:leer", "pedidos:crear", "pedidos:gestionar",
    "resenas:leer", "resenas:escribir", "resenas:moderar",
},
"cliente": {
    "ruta2:leer",
    "catalogo:usar",
    "pedidos:leer", "pedidos:crear",
    "resenas:leer", "resenas:escribir",
},
```

> Si te saltas este paso el login funciona pero **todo responde 403**. Es el
> error mas comun.

### Paso 4. Crear el `.env`

```powershell
cd P4
copy .env.example .env
```

Genera **tres secretos distintos** y pegalos en `JWT_SECRETO`, `AES_CLAVE` e
`INDICE_CIEGO_CLAVE`:

```powershell
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

No necesitas Neon: PostgreSQL corre en un contenedor y crea las cinco bases
de datos solo.

### Paso 5. Verificar la variable de la URL de autorizacion

Abre `P4/services/auth-service/.env.example` y busca como se llama la
variable que guarda la URL del microservicio de autorizacion. En
`docker-compose.yml`, el servicio `auth-service` envia cuatro nombres
posibles; deja el que corresponda y borra los otros.

### Paso 6. Levantar todo con un solo comando

```bash
cd P4
docker compose up --build
```

La primera vez tarda entre 3 y 6 minutos (descarga imagenes e instala
dependencias). Cuando el gateway imprime sus rutas, ya esta listo.

Abre **http://localhost:8080**

### Paso 7. Comprobar

```bash
curl http://localhost:8080/api/salud
```

Los seis servicios deben aparecer como `arriba`.

---

## Parte 2 — Usar

| Recurso | URL |
|---|---|
| Aplicacion | http://localhost:8080 |
| Salud del sistema | http://localhost:8080/api/salud |
| Diagnostico de permisos | http://localhost:8080/api/diagnostico |
| Swagger del servicio de autenticacion | http://localhost:8081/docs |
| Matriz de permisos vigente | http://localhost:8082/autorizacion/politicas |
| Sandbox GraphQL del catalogo | http://localhost:4001/graphql |
| GraphiQL del inventario | http://localhost:4002/graphql |
| Swagger de resenas | http://localhost:4004/docs |

Los puertos 4001–4004, 8081 y 8082 existen para revisar cada servicio por
separado. En un despliegue real se cierran: la unica puerta es el 8080.

### Comandos utiles

```bash
docker compose ps                        # que esta corriendo
docker compose logs -f gateway           # ver la bitacora del gateway
docker compose logs -f auth-service      # ver el retry loop hacia autorizacion
docker compose restart pedidos-service   # reiniciar un servicio
docker compose down                      # apagar
docker compose down -v                   # apagar y borrar los datos
```

---

## Parte 3 — Probar

### Prueba automatizada

Con el sistema arriba, en otra terminal:

```bash
bash scripts/prueba-humo.sh
```

```powershell
powershell -ExecutionPolicy Bypass -File scripts\prueba-humo.ps1
```

Recorre registro, login, 401 sin cookie, GraphQL en los dos servicios,
403 por rol, creacion de pedido con consulta al catalogo, cambio de estado y
las reglas de resenas. Termina con un resumen de aprobadas y fallidas.

### Recorrido manual de demostracion (6 minutos)

1. **Crear cuenta Admin.** Aterrizas en la barra de servicio. La tira de la
   derecha imprime cada llamada al gateway con su codigo.
2. **DevTools → Application → Cookies.** La cookie `acceso_token` tiene la
   marca **HttpOnly**; en la consola, `document.cookie` no la muestra.
3. **Menu.** Los datos vienen por GraphQL del `catalogo-service` (Node.js).
   Agotar y reponer un producto ejecuta una mutacion.
4. **Enviar un pedido.** El `pedidos-service` (REST) consulta el precio al
   catalogo antes de guardar: comunicacion directa entre microservicios.
5. **Inventario.** GraphQL del `inventario-service` (Python). Registrar una
   entrada cambia la existencia.
6. **Cerrar sesion y entrar como Cliente.** Pestana Inventario → **403** en
   la tira. Menu, pedidos y resenas siguen funcionando.
7. **Esperar 3 minutos** y pulsar cualquier pestana: la tira anota
   *token renovado* y la sesion continua sin volver a entrar.
8. **Detener el microservicio de autorizacion** y pulsar una pestana:

   ```bash
   docker compose stop authz-service
   ```

   El log del gateway muestra los reintentos con espera creciente y la
   respuesta final es **503**, no 403. Volver a levantarlo:

   ```bash
   docker compose start authz-service
   ```

9. **Pestana Sistema.** Muestra que servicio esta caido y que permisos
   concede el microservicio de autorizacion al rol actual.

---

## Parte 4 — Errores frecuentes

| Sintoma | Causa y solucion |
|---|---|
| Todo responde **403** despues del login | Faltan los permisos de P4 en `politicas.py`. Ver paso 3. Abre `/api/diagnostico` para ver cuales faltan. |
| Todo responde **503** | El microservicio de autorizacion no esta arriba: `docker compose ps authz-service`. |
| `502` con codigo `SESION_ILEGIBLE` | `/auth/yo` devuelve campos con otros nombres. Ajusta `normalizarSesion` en `gateway/src/sesion.js`. |
| El registro devuelve **422** | Los campos o los valores de rol de tu P2 se llaman distinto. Ajusta `CAMPOS` en `frontend/api.js`. |
| `auth-service` reinicia en bucle | Falta un secreto en `P4/.env` o son mas cortos de 32 caracteres. |
| `exec /app/docker-entrypoint.sh: no such file` | El script se clono con saltos de linea CRLF. El `.gitattributes` lo evita; si ya paso: `git add --renormalize .` |
| `port is already allocated` | Otro proceso ocupa 8080, 8000 o 5433. Cambia el lado izquierdo del mapeo en `docker-compose.yml`. |
| El navegador no manda la cookie | Estas abriendo el HTML con doble clic. Tiene que ser `http://localhost:8080`. |
| Cambie codigo y no se refleja | `docker compose up --build` reconstruye la imagen. |

---

## Parte 5 — Secuencia de commits

```powershell
cd Practicas-SA-B-202103763

git add P4/.gitignore P4/.gitattributes P4/.env.example
git commit -m "chore: estructura inicial de la practica 4"

git add P4/infra/
git commit -m "feat: postgres con base por servicio y edge nginx como salida publica"

git add P4/services/auth-service/ P4/services/authz-service/
git commit -m "feat: dockerizacion del modulo de autenticacion de la practica 2"

git add P4/services/catalogo-service/
git commit -m "feat: microservicio de catalogo con api graphql en node"

git add P4/services/inventario-service/
git commit -m "feat: microservicio de inventario con api graphql en python"

git add P4/services/pedidos-service/
git commit -m "feat: microservicio de pedidos con consulta directa al catalogo"

git add P4/services/resenas-service/
git commit -m "feat: microservicio de resenas con promedios por producto"

git add P4/gateway/
git commit -m "feat: api gateway con sesion, autorizacion y reintentos"

git add P4/frontend/
git commit -m "feat: frontend con comanda de trazas del gateway"

git add P4/docker-compose.yml
git commit -m "feat: orquestacion de los ocho servicios con docker compose"

git add P4/docs/ P4/k8s/ P4/scripts/ P4/README.md
git commit -m "docs: diagramas, contratos, guia y pruebas de humo"

git push
```

Antes del push, comprobar que no se sube ningun secreto:

```powershell
git ls-files | Select-String "\.env$"
```

No debe devolver nada.
