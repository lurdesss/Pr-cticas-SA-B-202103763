# Módulo de Autenticación y Autorización

Práctica 2: Software Avanzado, Segundo Semestre 2026
Universidad de San Carlos de Guatemala · Facultad de Ingeniería · Ingeniería en Ciencias y Sistemas

Módulo de registro y login con JWT en cookie HTTP-only, cifrado AES de datos sensibles, renovación automática de sesión y un microservicio de autorización independiente consultado mediante reintentos con backoff.

---

## Índice

1. [Cumplimiento de requisitos](#1-cumplimiento-de-requisitos)
2. [Arquitectura](#2-arquitectura)
3. [Stack tecnológico](#3-stack-tecnológico)
4. [Estructura del proyecto](#4-estructura-del-proyecto)
5. [Instalación paso a paso](#5-instalación-paso-a-paso)
6. [Ejecución](#6-ejecución)
7. [Endpoints](#7-endpoints)
8. [Seguridad implementada](#8-seguridad-implementada)
9. [Principios SOLID y código limpio](#9-principios-solid-y-código-limpio)
10. [Evidencia de pruebas](#10-evidencia-de-pruebas)
11. [Documentación de prompts de IA](#11-documentación-de-prompts-de-ia)

---

## 1. Cumplimiento de requisitos

| # | Requisito del enunciado | Dónde se implementa |
|---|---|---|
| 1 | Comunicación por API REST | `backend/app/api/routes/`, consumida desde `frontend/api.js` |
| 2 | Autenticación con JWT | `backend/app/services/token_service.py` |
| 3 | Token no visible para el usuario | Cookie `httponly=True` en `backend/app/api/deps.py` |
| 4 | Vida del JWT configurable por entorno | `JWT_TTL_SEGUNDOS` en `.env` |
| 5 | Renovación automática dentro de una ventana | `JWT_GRACIA_RENOVACION_SEGUNDOS`, lógica en `token_service.py` |
| 6 | Datos sensibles cifrados | AES-256-GCM en `backend/app/core/crypto.py` |
| 7 | Página de confirmación tras el login | `frontend/panel.html` |
| 8 | Dos endpoints protegidos por rol | `backend/app/api/routes/protegidas.py` |
| 9 | Microservicio de autorización con reintentos | `authz-service/` y `backend/app/infrastructure/authz_client.py` |

---

## 2. Arquitectura

Dos servicios independientes más un frontend estático:

```text
┌──────────────┐   fetch + cookie    ┌─────────────────────┐
│   Frontend   │ ──────────────────► │  Backend principal  │
│  (estático)  │ ◄────────────────── │  Autenticación      │
└──────────────┘   Set-Cookie        └──────────┬──────────┘
                   HTTP-only                    │
                                                │ POST /autorizacion/verificar
                                                │ con reintentos + backoff
                                                ▼
                                     ┌─────────────────────┐
                                     │   Microservicio de  │
                                     │    Autorización     │
                                     │  (matriz de roles)  │
                                     └─────────────────────┘
                        │
                        ▼
                 ┌─────────────┐
                 │ PostgreSQL  │  nombre y correo cifrados (AES-GCM)
                 └─────────────┘  contraseña hasheada (bcrypt)
```

**Por qué la autorización va aparte.** El backend sabe *quién* es el usuario (autenticación); el microservicio sabe *qué puede hacer* cada rol (autorización). Son preguntas distintas y cambian a ritmos distintos: la política de acceso se modifica con frecuencia, la lógica de login casi nunca. Separarlas permite ajustar permisos sin volver a desplegar el backend.

El backend **no tiene copia** de la matriz de permisos. Está obligado a preguntar, lo que impide que las dos versiones se desincronicen.

---

## 3. Stack tecnológico

| Componente | Tecnología | Por qué |
|---|---|---|
| Lenguaje | Python 3.11+ | Continuidad con la práctica 1; sin paso de compilación. |
| Framework | FastAPI | Inyección de dependencias nativa y Swagger automático. |
| Base de datos | PostgreSQL + SQLAlchemy 2.0 | Consultas parametrizadas por diseño. |
| JWT | PyJWT | Permite decodificar sin verificar expiración, necesario para la renovación. |
| Cifrado | `cryptography` (AES-256-GCM) | Cifrado autenticado: detecta manipulación del dato. |
| Contraseñas | passlib + bcrypt | Hash con sal automática y coste ajustable. |
| Cliente HTTP | httpx | Timeouts explícitos y excepciones tipadas para el retry loop. |
| Frontend | HTML + CSS + JavaScript sin framework | El requisito es funcional, no de UI; menos superficie que auditar. |

---

## 4. Estructura del proyecto

```text
P2/
├── backend/                      # Servicio de autenticación
│   ├── app/
│   │   ├── main.py
│   │   ├── core/
│   │   │   ├── config.py         # Variables de entorno validadas
│   │   │   ├── crypto.py         # AES-GCM, índice ciego y bcrypt
│   │   │   └── database.py
│   │   ├── domain/               # Núcleo sin dependencias externas
│   │   │   ├── entities.py       # Usuario, Rol
│   │   │   ├── repositories.py   # Contratos (incluye ClienteAutorizacion)
│   │   │   └── exceptions.py
│   │   ├── infrastructure/
│   │   │   ├── models.py
│   │   │   ├── postgres_repository.py
│   │   │   ├── memory_repository.py
│   │   │   └── authz_client.py   # Retry loop con backoff
│   │   ├── services/
│   │   │   ├── token_service.py  # Emisión, validación y renovación
│   │   │   └── auth_service.py   # Casos de uso
│   │   ├── schemas/auth.py
│   │   └── api/
│   │       ├── deps.py           # Cookie HTTP-only y guardas de permiso
│   │       ├── errors.py
│   │       └── routes/
│   │           ├── auth.py
│   │           └── protegidas.py
│   ├── tests/test_auth.py
│   ├── requirements.txt
│   ├── .env.example
│   └── scripts_init_db.py
├── authz-service/                # Microservicio de autorización
│   ├── app/
│   │   ├── main.py
│   │   └── politicas.py          # Matriz de permisos por rol
│   └── requirements.txt
├── frontend/
│   ├── index.html                # Login y registro
│   ├── panel.html                # Confirmación tras login (requisito 7)
│   ├── api.js, acceso.js, panel.js
│   └── estilos.css
├── sql/schema.sql
└── README.md
```

---

## 5. Instalación paso a paso

### 5.1 Requisitos previos

```bash
python --version   # 3.11 o superior
git --version
```

### 5.2 Backend

Desde `P2/backend`:

```bash
python -m venv .venv
```

```powershell
# Windows PowerShell
.venv\Scripts\Activate.ps1
```

```bash
# Linux / macOS
source .venv/bin/activate
```

```bash
pip install -r requirements.txt
```

### 5.3 Microservicio de autorización

En **otra terminal**, desde `P2/authz-service`:

```bash
python -m venv .venv
```

```powershell
.venv\Scripts\Activate.ps1
```

```bash
pip install -r requirements.txt
```

### 5.4 Base de datos

Igual que en la práctica 1: crear un proyecto en [neon.tech](https://neon.tech), copiar la cadena de conexión y cambiar el prefijo `postgresql://` por `postgresql+psycopg://`.

### 5.5 Variables de entorno

```bash
# Windows
copy .env.example .env
# Linux / macOS
cp .env.example .env
```

Generar tres secretos **distintos** entre sí:

```bash
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

Colocarlos en `JWT_SECRETO`, `AES_CLAVE` e `INDICE_CIEGO_CLAVE`. Usar el mismo valor en los tres reduce el margen de maniobra ante una filtración: comprometer uno comprometería las tres funciones.

Los tiempos recomendados para la revisión:

```env
JWT_TTL_SEGUNDOS=180                  # 3 minutos
JWT_GRACIA_RENOVACION_SEGUNDOS=60     # 1 minuto de gracia
```

Con estos valores la sesión dura 3 minutos y admite renovación durante 1 minuto más, lo que da margen de sobra para una demostración de 10 minutos sin tener que reiniciar sesión constantemente.

### 5.6 Crear la tabla

```bash
python scripts_init_db.py
```

O pegar `sql/schema.sql` en el editor SQL de Neon.

---

## 6. Ejecución

Se necesitan **tres terminales**.

**Terminal 1 — microservicio de autorización (puerto 8001):**

```bash
cd authz-service
uvicorn app.main:app --port 8001 --reload
```

**Terminal 2 — backend (puerto 8000):**

```bash
cd backend
uvicorn app.main:app --port 8000 --reload
```

**Terminal 3 — frontend (puerto 5500):**

```bash
cd frontend
python -m http.server 5500
```

> El frontend debe servirse por HTTP, no abriendo el archivo con doble clic. Un archivo abierto como `file://` tiene origen `null`, y el navegador se niega a enviar cookies desde ahí.

| Recurso | URL |
|---|---|
| Aplicación | http://127.0.0.1:5500 |
| API del backend | http://127.0.0.1:8000/docs |
| Microservicio de autorización | http://127.0.0.1:8001/docs |
| Matriz de permisos vigente | http://127.0.0.1:8001/autorizacion/politicas |

### Recorrido de demostración

1. Crear una cuenta con rol **Admin** → redirige a la página de confirmación.
2. Probar ruta 1 y ruta 2: ambas responden 200.
3. Cerrar sesión, crear una cuenta con rol **Cliente**.
4. Probar ruta 1 → **403**. Probar ruta 2 → **200**.
5. Esperar a que el contador pase a "Expirado · renovable" y pulsar cualquier ruta: la bitácora registra *token renovado automáticamente* y el contador se reinicia.
6. Esperar a que el contador llegue a "fuera de la ventana de gracia" y volver a pulsar: **401** y regreso al acceso.
7. Detener el microservicio de autorización (Ctrl+C en la terminal 1) y pulsar una ruta: tras los reintentos, **503**.

---

## 7. Endpoints

### Backend (puerto 8000)

| Método | Ruta | Descripción | Éxito | Errores |
|---|---|---|---|---|
| `POST` | `/auth/registro` | Crea la cuenta y abre sesión. | `201` | `409`, `422` |
| `POST` | `/auth/login` | Valida credenciales y entrega la cookie. | `200` | `401`, `422` |
| `GET` | `/auth/yo` | Datos de la sesión activa. | `200` | `401` |
| `POST` | `/auth/logout` | Borra la cookie. | `200` | — |
| `GET` | `/recursos/ruta1` | Solo Admin. | `200` | `401`, `403`, `503` |
| `GET` | `/recursos/ruta2` | Admin y Cliente. | `200` | `401`, `403`, `503` |

### Microservicio de autorización (puerto 8001)

| Método | Ruta | Descripción |
|---|---|---|
| `POST` | `/autorizacion/verificar` | Recibe `{rol, permiso}` y responde `{permitido}`. |
| `GET` | `/autorizacion/politicas` | Expone la matriz de permisos, útil para auditoría. |

### Matriz de acceso

| Rol | Ruta 1 (`ruta1:leer`) | Ruta 2 (`ruta2:leer`) |
|---|---|---|
| Admin | Permitido | Permitido |
| Cliente | Denegado | Permitido |

---

## 8. Seguridad implementada

### 8.1 El token no es accesible desde el navegador

```python
# backend/app/api/deps.py
respuesta.set_cookie(
    key=settings.cookie_nombre,
    value=token,
    httponly=True,      # document.cookie no puede leerlo
    secure=settings.cookie_secure,
    samesite=settings.cookie_samesite,
    max_age=settings.jwt_ttl_segundos + settings.jwt_gracia_renovacion_segundos,
    path="/",
)
```

`httponly=True` es lo que cumple el requisito 3: aunque una vulnerabilidad de XSS logre ejecutar JavaScript en la página, ese script no puede leer el token ni enviarlo a otro servidor. Guardarlo en `localStorage` habría dejado el token expuesto a cualquier script cargado en la página.

`max_age` es deliberadamente **mayor** que la vida del JWT. Si la cookie caducara junto con el token, el navegador dejaría de enviarla justo cuando el backend necesita recibirla para renovarla, y la ventana de gracia nunca llegaría a usarse.

### 8.2 Renovación automática dentro de la ventana de gracia

Línea de tiempo de un token:

```text
emisión                 exp                  exp + gracia
   |------- válido -------|--- renovable ---|--- rechazado --->
```

```python
# backend/app/services/token_service.py
def verificar(self, token: str) -> Credencial | None:
    try:
        cuerpo = self._decodificar(token, verificar_expiracion=True)
        return self._construir_credencial(cuerpo, ResultadoToken.VALIDO)

    except jwt.ExpiredSignatureError:
        return self._evaluar_ventana_de_gracia(token)

    except jwt.InvalidTokenError:
        return None
```

El punto delicado está en `_evaluar_ventana_de_gracia`: para saber *cuándo* expiró el token hay que decodificarlo, pero ya está expirado. Se vuelve a decodificar desactivando **únicamente** la comprobación de expiración:

```python
return jwt.decode(
    token,
    self._settings.jwt_secreto,
    algorithms=[self._settings.jwt_algoritmo],
    options={"verify_exp": verificar_expiracion, "require": ["sub", "exp"]},
)
```

La verificación de firma sigue activa. Un token expirado **y además falsificado** se rechaza igual: la ventana de gracia relaja el tiempo, nunca la autenticidad.

La renovación es transparente para el cliente. La dependencia que protege las rutas reescribe la cookie cuando corresponde:

```python
# backend/app/api/deps.py
sesion = servicio.validar_sesion(acceso_token)

if sesion.token_renovado is not None:
    escribir_cookie_sesion(respuesta, sesion.token_renovado, settings)
    respuesta.headers["X-Token-Renovado"] = "true"
```

### 8.3 Cifrado AES de datos sensibles

Se emplean tres mecanismos distintos, cada uno para lo que corresponde:

| Dato | Mecanismo | Por qué |
|---|---|---|
| Nombre, correo | AES-256-GCM | Deben poder recuperarse en claro para mostrarlos. |
| Correo (búsqueda) | HMAC-SHA256 | Permite buscar sin descifrar la tabla completa. |
| Contraseña | bcrypt | Debe ser irreversible incluso para el propio sistema. |

**Por qué la contraseña se hashea y no se cifra.** El enunciado menciona las contraseñas entre los datos a almacenar cifrados. Cifrarlas sería un error de seguridad: el cifrado es reversible, de modo que quien obtuviera la clave AES recuperaría todas las contraseñas en claro. Un hash bcrypt no puede revertirse ni siquiera conociendo la configuración del sistema, y para verificar un login no hace falta recuperar la contraseña original: basta con comparar hashes. Se aplicó el criterio técnicamente correcto y queda documentado aquí de forma explícita.

**Por qué hace falta el índice ciego.** AES-GCM usa un nonce aleatorio distinto en cada operación, así que cifrar el mismo correo dos veces produce dos textos diferentes. Eso es correcto y deseable —impide deducir que dos filas contienen el mismo valor—, pero vuelve imposible un `WHERE correo_cifrado = ...`. La solución es guardar además un HMAC determinista del correo normalizado:

```python
# backend/app/core/crypto.py
def indice_ciego(valor: str) -> str:
    clave = _derivar_clave(get_settings().indice_ciego_clave)
    normalizado = valor.strip().lower().encode("utf-8")
    return hmac.new(clave, normalizado, hashlib.sha256).hexdigest()
```

Es un HMAC con clave propia y no un SHA-256 simple: sin la clave, quien obtenga un volcado de la base de datos no puede confirmar si un correo concreto está registrado probando candidatos.

Se eligió el modo **GCM** y no CBC porque GCM es cifrado autenticado: si alguien altera un byte del registro directamente en la base de datos, el descifrado falla en lugar de devolver datos corruptos en silencio.

### 8.4 Reintentos con backoff hacia el servicio de autorización

```python
# backend/app/infrastructure/authz_client.py
espera = self._backoff_inicial

for intento in range(1, self._max_reintentos + 1):
    respuesta = self._consultar_una_vez(rol, permiso, intento)
    if respuesta is not None:
        return respuesta

    if intento < self._max_reintentos:
        time.sleep(espera)
        espera *= self._backoff_factor

raise ServicioAutorizacionNoDisponibleError(self._max_reintentos)
```

Con la configuración por defecto (4 intentos, 200 ms iniciales, factor 2) las esperas son 200 ms, 400 ms y 800 ms.

La distinción que sostiene el diseño es entre **dos fallos que no deben confundirse**:

| Situación | Respuesta | ¿Se reintenta? |
|---|---|---|
| El servicio responde "sin permiso" | `403` | No: la respuesta es definitiva. |
| El servicio no responde (timeout, 5xx) | `503` | Sí, hasta agotar los intentos. |

Devolver `403` cuando el microservicio está caído sería engañoso: le diría al usuario que carece de permisos, cuando en realidad nadie pudo comprobarlo. El código que lo separa es explícito:

```python
if respuesta.status_code >= 500:
    return None          # transitorio: reintentar
if respuesta.status_code != httpx.codes.OK:
    return False         # 4xx: reintentar no lo arregla
```

### 8.5 Otras defensas

| Riesgo (OWASP Top 10) | Mitigación |
|---|---|
| A01 — Control de acceso roto | Cada ruta declara el permiso que exige; el veredicto lo da un servicio externo. |
| A02 — Fallos criptográficos | AES-256-GCM para datos, bcrypt para contraseñas, secretos fuera del código. |
| A03 — Inyección SQL | Consultas con el lenguaje de expresiones de SQLAlchemy, sin concatenar texto. |
| A05 — Configuración insegura | El manejador global registra la traza y devuelve un mensaje genérico. |
| A07 — Fallos de identificación | Mismo mensaje para correo inexistente y contraseña incorrecta. |

Sobre A07: si el sistema respondiera "ese correo no existe", cualquiera podría averiguar qué correos están registrados probando uno por uno. Por eso ambos casos comparten una única excepción:

```python
# backend/app/services/auth_service.py
if usuario is None or not verificar_password(password, usuario.password_hash):
    raise CredencialesInvalidasError
```

---

## 9. Principios SOLID y código limpio

| Principio | Dónde se evidencia |
|---|---|
| **S** — Responsabilidad única | `token_service.py` solo firma y valida tokens; `crypto.py` solo cifra; `authz_client.py` solo habla con el microservicio; los endpoints solo traducen HTTP. |
| **O** — Abierto/cerrado | `exigir_permiso(permiso)` es una fábrica de guardas: agregar una ruta protegida nueva no modifica ningún código existente. La matriz de permisos crece añadiendo entradas en `politicas.py`. |
| **L** — Sustitución de Liskov | `RepositorioUsuariosMemoria` y `RepositorioUsuariosPostgres` cumplen el mismo contrato; las pruebas corren con el primero sin tocar el servicio. |
| **I** — Segregación de interfaces | El repositorio se divide en `LectorUsuarios` y `EscritorUsuarios`; `ClienteAutorizacion` expone un único método. |
| **D** — Inversión de dependencias | `ServicioAutenticacion` recibe abstracciones por constructor y no importa httpx, SQLAlchemy ni FastAPI. |

El ejemplo más claro de OCP:

```python
# backend/app/api/deps.py
def exigir_permiso(permiso: str) -> Callable[..., Usuario]:
    def guarda(usuario: UsuarioActualDep, servicio: ServicioAuthDep) -> Usuario:
        servicio.exigir_permiso(usuario, permiso)
        return usuario
    return guarda
```

```python
# backend/app/api/routes/protegidas.py
@router.get("/ruta1", response_model=RecursoProtegidoRespuesta)
def ruta_solo_admin(
    usuario: Annotated[Usuario, Depends(exigir_permiso(PERMISO_RUTA1))],
) -> RecursoProtegidoRespuesta:
    ...
```

El endpoint no sabe qué roles existen. Solo declara el permiso que necesita.

Prácticas de código limpio aplicadas: nombres descriptivos en español sin abreviaturas, ninguna función por encima de 25 líneas, tipado completo, sin números mágicos (los tiempos vienen del entorno, los estados de enumerados), manejo de errores centralizado, y comentarios que justifican decisiones en lugar de describir lo que el código ya dice.

---

## 10. Evidencia de pruebas

### 10.1 Suite automatizada

```bash
cd backend
pytest -q
```

```text
16 passed
```

Las pruebas cubren cifrado reversible, no determinismo de AES-GCM, determinismo del índice ciego, hash de contraseñas, los tres estados del token, rechazo de firma alterada, login correcto e incorrecto, correo duplicado, renovación dentro de la gracia, acceso por rol y caída del servicio de autorización.

```bash
ruff check .
```

```text
All checks passed!
```

### 10.2 Verificación funcional

| # | Escenario | Esperado | Obtenido |
|---|---|---|---|
| 1 | Registro de Admin | `201` + cookie HttpOnly | `201` |
| 2 | El token no aparece en el cuerpo | ausente | ausente |
| 3 | `GET /auth/yo` con cookie | `200` | `200` |
| 4 | Admin → ruta 1 | `200` | `200` |
| 5 | Admin → ruta 2 | `200` | `200` |
| 6 | Cliente → ruta 1 | `403` | `403` |
| 7 | Cliente → ruta 2 | `200` | `200` |
| 8 | Token expirado dentro de la gracia | `200` + renovación | `200`, `X-Token-Renovado: true` |
| 9 | Petición sin cookie | `401` | `401` |
| 10 | Contraseña incorrecta | `401` | `401` |
| 11 | Correo inexistente | mismo mensaje que el anterior | idéntico |
| 12 | Correo duplicado | `409` | `409` |
| 13 | Contraseña de menos de 8 caracteres | `422` | `422` |
| 14 | Rol inexistente | `422` | `422` |
| 15 | Servicio de autorización caído | `503` tras 4 intentos | `503` |

Salida del escenario 8, que demuestra la renovación automática:

```text
=== RENOVACION: espero 4s (ttl=2, gracia=10) ===
status: 200 | X-Token-Renovado: true
nueva cookie emitida: True
```

Salida del escenario 15, con el retry loop y el backoff visibles en el log del backend:

```text
WARNING  Autorización sin respuesta (intento 1/4). Reintentando en 0.20 s.
WARNING  Autorización sin respuesta (intento 2/4). Reintentando en 0.40 s.
WARNING  Autorización sin respuesta (intento 3/4). Reintentando en 0.80 s.
ERROR    Autorización agotó 4 intentos para rol=admin permiso=ruta1:leer.

503 {'detalle': 'El servicio de autorización no respondió tras 4 intentos.'}
```

Nótese que el código es `503` y no `403`: el acceso no se denegó por falta de permisos.

Comprobación de que los datos llegan cifrados a la base de datos:

```sql
SELECT correo_cifrado, correo_indice, password_hash FROM usuarios LIMIT 1;
```

El correo aparece como base64 ilegible, el índice como 64 caracteres hexadecimales, y el hash comenzando con `$2b$`.

---

## 11. Documentación de prompts de IA

Se utilizó Claude (Anthropic) como apoyo, avanzando por incrementos verificables en lugar de pedir el módulo completo de una vez. Cada prompt siguió la estructura **rol → contexto → restricciones → alcance acotado → formato de salida**.

---

### Prompt 1 — Arquitectura y separación de servicios (sin código)

```text
Actúa como arquitecto de software backend especializado en seguridad de
aplicaciones web.

Contexto: debo implementar un módulo de registro y login con dos roles
(Admin y Cliente) y dos rutas protegidas. Restricciones impuestas por el
enunciado:
- Autenticación con JWT, con el token NO accesible por el usuario.
- Vida del token y ventana de renovación configurables por variable de
  entorno.
- Datos sensibles cifrados en base de datos (se sugiere AES).
- La autorización debe ser un microservicio independiente, consultado con
  reintentos y backoff.

Stack: Python 3.11, FastAPI, PostgreSQL, SQLAlchemy 2.0.

Tarea (solo esta):
1. Propón la separación entre servicio de autenticación y microservicio de
   autorización, indicando qué información conoce cada uno y qué NO debe
   conocer.
2. Explica dónde debe almacenarse el token para que el usuario no pueda
   leerlo, comparando las alternativas y sus riesgos.
3. Señala qué partes del enunciado podrían implementarse de forma
   literal pero técnicamente incorrecta.

NO escribas código todavía.
```

**Respuesta obtenida:** propuso que el microservicio solo reciba `{rol, permiso}` y no conozca usuarios ni base de datos. Comparó `localStorage` (legible por cualquier script, vulnerable a XSS) con cookie HTTP-only, recomendando la segunda. En el punto 3 señaló que almacenar contraseñas cifradas con AES, aunque el enunciado las menciona entre los datos sensibles, sería un error: el cifrado es reversible y una filtración de la clave expondría todas las contraseñas.

**Análisis crítico y ajustes aplicados:**

- Acepté la advertencia sobre las contraseñas y usé bcrypt, dejando la justificación documentada en la sección 8.3 para que la desviación respecto del enunciado sea explícita y no parezca un descuido.
- **Detecté un vacío en la propuesta:** describía cifrar el correo con AES pero no explicaba cómo buscar por correo en el login, algo imposible con AES-GCM porque el texto cifrado cambia en cada operación. Investigué el patrón de índice ciego y lo añadí por decisión propia; sin él, el login habría requerido descifrar la tabla entera en cada intento.
- Rechacé una sugerencia de guardar también un *refresh token* aparte: el enunciado pide renovación por ventana de gracia, que es un mecanismo distinto, y mantener ambos habría duplicado la superficie de ataque sin ser requerido.

---

### Prompt 2 — Servicio de tokens con renovación

```text
Implementa ÚNICAMENTE app/services/token_service.py.

Requisitos funcionales:
- Emitir un JWT con sub (id de usuario), rol, iat y exp.
- Al verificar, distinguir TRES estados: válido, expirado-pero-renovable
  (dentro de una ventana de gracia configurable) y rechazado.

Requisitos de seguridad (obligatorios):
- Para evaluar la ventana de gracia hay que decodificar un token ya
  expirado. Al hacerlo, la verificación de FIRMA debe seguir activa: un
  token expirado y falsificado debe rechazarse igual.
- El algoritmo de verificación debe estar fijado explícitamente, no
  tomarse del propio token.
- No capturar excepciones de forma genérica.

Requisitos de diseño:
- La configuración se recibe por constructor, no se lee de una variable
  global, para que las pruebas puedan usar tiempos cortos.
- Ninguna función debe superar las 20 líneas.

Después de escribirlo, dime qué pasa si alguien envía un token firmado
con otro algoritmo, y si tu código lo previene.
```

**Respuesta obtenida:** entregó la clase con el enumerado de tres estados y la doble decodificación. En la autorrevisión explicó que fijar `algorithms=[...]` previene el ataque de confusión de algoritmos, en el que un atacante cambia la cabecera a `none` o a `HS256` usando la clave pública como secreto.

**Análisis crítico y ajustes aplicados:**

- **Verificación independiente:** no me quedé con la explicación. Escribí una prueba que altera la firma de un token válido y confirmé que se rechaza (`test_token_con_firma_alterada_se_rechaza`).
- **Corrección aplicada por mí:** la versión generada no incluía `require: ["sub", "exp"]` en las opciones de decodificación. Un token firmado correctamente pero sin el campo `exp` habría llegado hasta `_evaluar_ventana_de_gracia` y provocado un error 500 al buscar una clave inexistente. Lo añadí para que se rechace desde la decodificación.
- **Corrección de tipos:** el borrador devolvía el diccionario del token directamente hacia el servicio. Eso filtra la estructura del JWT a capas que no deberían conocerla; introduje la `dataclass` `Credencial` como frontera.

---

### Prompt 3 — Cliente de autorización con reintentos

```text
Implementa app/infrastructure/authz_client.py, que cumple la interfaz
ClienteAutorizacion ya definida en el dominio.

Requisito del enunciado: consultar el microservicio con un ciclo de
reintentos y backoff configurables antes de denegar el acceso por error
de comunicación.

Restricciones (obligatorias):
- Distingue con claridad dos casos: el servicio responde "sin permiso"
  (respuesta definitiva, NO reintentar) y el servicio no responde
  (transitorio, SÍ reintentar).
- Un fallo de red NO debe traducirse en 403. Lanza una excepción propia
  que la capa de API convierta en 503.
- Timeout explícito en cada intento.
- Máximo de reintentos, espera inicial y factor de backoff configurables.

Enumérame qué excepciones concretas de httpx debes capturar para el
reintento y cuáles NO, con la razón de cada una.
```

**Respuesta obtenida:** el cliente con el bucle de reintentos y la separación entre veredicto y fallo de transporte. Enumeró `TimeoutException` y `TransportError` como candidatas a reintento, y descartó `HTTPStatusError` en 4xx porque indica una petición mal formada que no mejorará al repetirse.

**Análisis crítico y ajustes aplicados:**

- **Vulnerabilidad de disponibilidad detectada por mí:** el borrador trataba los códigos 5xx como respuesta definitiva y devolvía `False`. Un error temporal del microservicio habría denegado accesos legítimos de forma silenciosa. Cambié el flujo para que 5xx se considere transitorio y entre en el ciclo de reintentos.
- **Corrección de robustez:** no contemplaba que el servicio respondiera `200` con un cuerpo que no fuese JSON válido. Añadí la captura de `ValueError` para tratarlo como intento fallido en lugar de dejar que la excepción escalara como error 500.
- Ajusté el bucle para que no espere después del último intento: la versión original dormía una vez más antes de lanzar la excepción, retrasando la respuesta sin ninguna utilidad.

---

### Prompt 4 — Auditoría de seguridad del módulo completo

```text
Actúa como revisor de seguridad con el OWASP Top 10 como marco. Te
comparto el módulo completo: configuración, cifrado, servicio de tokens,
servicio de autenticación, dependencias de FastAPI y endpoints.

No reescribas el proyecto. Entrégame:
1. Tabla de hallazgos: severidad, archivo, categoría OWASP y el cambio
   mínimo que corrige cada uno.
2. Puntos donde el manejo de la cookie o del ciclo de vida del token
   podría dejar una sesión viva más tiempo del debido.
3. Falsos positivos: cosas que parecen problemas pero no lo son aquí,
   con su justificación.
```

**Respuesta obtenida:**

| Severidad | Hallazgo |
|---|---|
| Alta | El login revelaba si un correo existía, permitiendo enumerar usuarios (A07). |
| Media | La cookie caducaba junto con el JWT, impidiendo aprovechar la ventana de gracia. |
| Media | Sin `max_length` en los campos de texto, admitiendo cargas de gran tamaño. |
| Baja | Sugerencia de añadir rotación de secretos y lista de revocación de tokens. |

**Análisis crítico y ajustes aplicados:**

- **Aceptado (alta):** unifiqué el error de correo inexistente y contraseña incorrecta en una sola excepción. Era un fallo real que yo había pasado por alto y que se comprueba en `test_correo_inexistente_da_el_mismo_error`.
- **Aceptado (media):** el hallazgo sobre la cookie era correcto y sutil. Con `max_age` igual al TTL del JWT, el navegador borraba la cookie justo cuando el backend la necesitaba para renovarla, y la ventana de gracia quedaba muerta en la práctica. Ajusté `max_age` a `ttl + gracia`.
- **Aceptado (media):** añadí `max_length` a nombre y contraseña, este último alineado con el límite real de 72 bytes de bcrypt.
- **Rechazado con justificación (baja):** no implementé lista de revocación. Requiere almacenamiento compartido y un mecanismo de limpieza, y con tokens de 3 minutos la ventana de exposición de un token robado ya es muy corta. Queda anotado como el siguiente paso si los tiempos se alargan.
- **Falso positivo señalado correctamente:** marcó `cookie_secure=false` como riesgo. Es correcto en producción, pero en desarrollo local sobre HTTP una cookie `Secure` no se enviaría nunca y nada funcionaría. Por eso es configurable y el `.env.example` documenta que debe valer `true` con HTTPS.

---

### Hallazgo adicional durante las pruebas

Al ejecutar la prueba de integración por primera vez, las seis peticiones a rutas protegidas devolvieron `503` en lugar de los `200` y `403` esperados. El log mostró el ciclo de reintentos completo:

```text
Autorización sin respuesta (intento 1/4). Reintentando en 0.20 s.
Autorización sin respuesta (intento 2/4). Reintentando en 0.40 s.
Autorización sin respuesta (intento 3/4). Reintentando en 0.80 s.
Autorización agotó 4 intentos.
```

La causa no era un defecto del código: el microservicio de autorización no estaba levantado. El episodio resultó útil por dos motivos. Confirmó que el retry loop y el backoff exponencial funcionan exactamente como exige el requisito 9, y verificó que un fallo de infraestructura se reporta como `503` y no como `403`, que era precisamente la distinción de diseño que se quería garantizar.

Se conservó como escenario 15 de la evidencia de pruebas.

---

### Conclusión sobre el uso de IA

La herramienta aceleró la escritura y detectó un fallo real de enumeración de usuarios que yo había pasado por alto. Pero produjo también cinco defectos que solo aparecieron al revisar: la omisión de campos obligatorios en la decodificación del token, la filtración del diccionario del JWT hacia el servicio, el tratamiento de los errores 5xx como definitivos, la falta de manejo de respuestas no interpretables, y una espera inútil tras el último reintento. A eso se suma un vacío de diseño —cómo buscar por un correo cifrado— que no señaló y que había que resolver para que el login funcionara.

El patrón se repitió respecto de la práctica anterior: el código generado tiende a ser correcto en el camino feliz y frágil en los bordes. Los prompts que más valor aportaron fueron los que exigían a la herramienta **auditar su propio resultado** con una pregunta concreta ("¿qué pasa si el token viene firmado con otro algoritmo?"), porque obligan a explicitar supuestos que de otro modo quedan implícitos en el código.

---

## Autor

**Nombre:** Jennifer Yulissa Lourdes Taperio Manuel

**Carné:** 202103763

**Sección:** B

**Curso:** Software Avanzado — Segundo Semestre 2026
