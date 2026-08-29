# Aroma — Sistema de microservicios para una cafeteria de especialidad

Práctica 4: Software Avanzado, Segundo Semestre 2026
Universidad de San Carlos de Guatemala · Facultad de Ingeniería · Ingeniería en Ciencias y Sistemas

Seis microservicios en dos lenguajes, integrados por un API Gateway,
orquestados con Docker Compose y protegidos por el módulo de autenticación
desarrollado en la Práctica 2.

---

## Índice

1. [Cumplimiento de requisitos](#1-cumplimiento-de-requisitos)
2. [El sistema](#2-el-sistema)
3. [Arquitectura](#3-arquitectura)
4. [Stack tecnológico](#4-stack-tecnológico)
5. [Estructura del proyecto](#5-estructura-del-proyecto)
6. [Instalación y ejecución](#6-instalación-y-ejecución)
7. [Endpoints y contratos](#7-endpoints-y-contratos)
8. [Integración del módulo de autenticación](#8-integración-del-módulo-de-autenticación)
9. [Principios SOLID](#9-principios-solid)
10. [Evidencia de pruebas](#10-evidencia-de-pruebas)
11. [Documentación de prompts de IA](#11-documentación-de-prompts-de-ia)

---

## 1. Cumplimiento de requisitos

| # | Requisito del enunciado | Dónde se implementa |
|---|---|---|
| 1 | Mínimo 4 microservicios funcionales | `services/catalogo-service`, `services/inventario-service`, `services/pedidos-service`, `services/resenas-service` (más `auth-service` y `authz-service`) |
| 2 | Al menos un endpoint funcional por servicio | Cada servicio expone su API y una sonda `/salud` |
| 3 | Integrar el servicio de autenticación de la Práctica 2 | `services/auth-service/` + `services/authz-service/`, consumidos por `gateway/src/sesion.js` |
| 4 | Dockerfile individual por microservicio | Ocho Dockerfile, uno por carpeta de servicio, más el del edge |
| 5 | API Gateway funcional que consuma todos los microservicios | `gateway/`, mapa declarativo en `gateway/src/rutas.js` |
| 6 | Al menos 2 lenguajes de programación distintos | Node.js (gateway, catálogo, pedidos) y Python (autenticación, autorización, inventario, reseñas) |
| 7 | Docker Compose que levante todo con un solo comando | `docker-compose.yml`: `docker compose up --build` |
| 8 | GraphQL en al menos 2 servicios | `catalogo-service` (Apollo Server) e `inventario-service` (Strawberry) |
| 9 | Diagrama de arquitectura | [docs/arquitectura.md](docs/arquitectura.md#1-diagrama-de-arquitectura-comunicación-entre-servicios) |
| 10 | Diagrama de despliegue | [docs/arquitectura.md](docs/arquitectura.md#2-diagrama-de-despliegue) |
| 11 | Diagrama ER completo | [docs/arquitectura.md](docs/arquitectura.md#3-diagrama-entidad-relación), una base por servicio |
| 12 | Contrato de microservicios en Swagger o Postman | [docs/openapi-gateway.yaml](docs/openapi-gateway.yaml) y [docs/postman_collection.json](docs/postman_collection.json) |
| 13 | Documentación técnica completa | Este README, más `docs/` |
| 14 | Explicación propia de los 5 principios SOLID con código real | [Sección 9](#9-principios-solid) |
| 15 | *Recomendado:* comunicación directa entre microservicios | `pedidos-service` consulta el precio al `catalogo-service` (`services/pedidos-service/src/catalogo.js`) |
| 16 | *Recomendado:* base de datos separada por servicio | Cinco bases distintas: `infra/postgres/init/00-bases.sql` |

---

## 2. El sistema

**Aroma** es una cafetería de especialidad. El sistema cubre lo que ocurre
detrás de la barra:

| Microservicio | Qué resuelve | API | Lenguaje |
|---|---|---|---|
| `auth-service` | Quién eres. Registro, login, cookie HttpOnly, renovación del token. | REST | Python |
| `authz-service` | Qué puedes hacer. Matriz de permisos por rol. | REST | Python |
| `catalogo-service` | El menú: categorías, productos, precios, disponibilidad. | **GraphQL** | Node.js |
| `inventario-service` | La bodega: insumos, existencias, entradas y salidas. | **GraphQL** | Python |
| `pedidos-service` | La comanda: pedidos, items, estados. | REST | Node.js |
| `resenas-service` | Lo que opina la gente: calificaciones y promedios. | REST | Python |
| `gateway` | Puerta única: sesión, permisos, enrutado. | REST | Node.js |
| `edge` | Salida al exterior: sirve el frontend y publica `/api`. | nginx | — |

Dos roles, heredados de la Práctica 2:

| Rol | Puede |
|---|---|
| **Admin** | Todo: gestionar menú, bodega, estados de pedidos y moderar reseñas. |
| **Cliente** | Ver el menú, pedir, ver sus propios pedidos y escribir reseñas. |

---

## 3. Arquitectura

```text
                    ┌──────────────────────────┐
   Navegador  ────► │  edge (nginx) · :8080    │  ← único puerto público
                    │  frontend + /api         │
                    └────────────┬─────────────┘
                                 │
                    ┌────────────▼─────────────┐
                    │      API Gateway         │
                    │  1. ¿quién eres?  ───────┼──► auth-service   (P2)
                    │  2. ¿qué puedes?  ───────┼──► authz-service  (P2)
                    │  3. reenvía con identidad│      reintentos + backoff
                    └────────────┬─────────────┘
                                 │
        ┌──────────────┬─────────┴─────┬──────────────┐
        ▼              ▼               ▼              ▼
   catalogo       inventario       pedidos        resenas
   GraphQL        GraphQL          REST           REST
   Node.js        Python           Node.js        Python
        │              │               │  ▲           │
        │              │               │  │ precio    │
        │              │               └──┘ vigente   │
        ▼              ▼               ▼              ▼
   catalogo_db   inventario_db    pedidos_db     resenas_db
```

Los tres diagramas formales (arquitectura, despliegue y ER) están en
**[docs/arquitectura.md](docs/arquitectura.md)** en formato Mermaid, que
GitHub renderiza directamente.

### Las tres decisiones que sostienen el diseño

**El gateway no abre el JWT.** Podría: tiene acceso a la red y bastaría
compartirle el secreto. Pero entonces la lógica de la ventana de gracia de
la Práctica 2 tendría dos implementaciones que se desincronizarían. En vez
de eso, el gateway le pregunta a `/auth/yo` y reenvía la cookie renovada si
viene una. El servicio de autenticación sigue siendo el único que conoce el
secreto.

**Autenticación y autorización siguen separadas.** Es la misma decisión de
la Práctica 2, y aquí se paga sola: agregar los ocho permisos de la Práctica
4 fue editar un diccionario en `politicas.py`. Ni el gateway ni ningún
microservicio se recompiló.

**Un fallo de comunicación nunca se disfraza de falta de permiso.** Si el
microservicio de autorización no responde, el gateway reintenta con espera
creciente y termina en `503`. Un `403` afirmaría que el usuario no tiene
permiso; `503` admite que nadie pudo comprobarlo.

---

## 4. Stack tecnológico

| Componente | Tecnología | Por qué |
|---|---|---|
| Contenedores | Docker + Docker Compose | Requisito, y lo único que garantiza que ocho servicios arranquen igual en cualquier máquina. |
| Gateway | Node.js 20 + Express + http-proxy-middleware | El gateway es casi puro trabajo de E/S; el modelo asíncrono de Node encaja sin esfuerzo. |
| Catálogo | Node.js + Apollo Server 4 | Implementación de referencia de GraphQL en el ecosistema JavaScript. |
| Inventario | Python 3.11 + FastAPI + Strawberry | Demuestra GraphQL en el otro lenguaje, con tipado estático real. |
| Pedidos | Node.js + Express | REST simple con transacciones sobre PostgreSQL. |
| Reseñas | Python + FastAPI + SQLAlchemy 2.0 | Validación declarativa con Pydantic y Swagger automático. |
| Autenticación | Python + FastAPI (Práctica 2) | Se reutiliza sin reescribir: solo se dockeriza. |
| Base de datos | PostgreSQL 16 | Una base por servicio dentro de una sola instancia. |
| Salida pública | nginx | Sirve el frontend y unifica el origen con la API, lo que elimina el CORS. |
| Frontend | HTML + CSS + JavaScript sin framework | El requisito es funcional; menos superficie que auditar. |

### Por qué dos lenguajes y no uno

El requisito pide dos como mínimo, pero el reparto no es arbitrario. Node.js
quedó en los servicios dominados por espera de red: el gateway, que no hace
más que reenviar, y el catálogo, que sirve lecturas. Python quedó en los
servicios con reglas de negocio y aritmética —el inventario descuenta
existencias y valida que no queden negativas, las reseñas agregan
promedios— y, sobre todo, en el módulo de autenticación, que se heredó sin
tocar una línea.

---

## 5. Estructura del proyecto

```text
P4/
├── docker-compose.yml            # levanta los 9 contenedores
├── .env.example                  # secretos y tiempos (copiar a .env)
├── README.md
│
├── gateway/                      # API Gateway · Node.js
│   ├── Dockerfile
│   ├── package.json
│   └── src/
│       ├── index.js              # composición de la aplicación
│       ├── config.js             # todo por variables de entorno
│       ├── rutas.js              # mapa declarativo prefijo → servicio → permiso
│       ├── sesion.js             # ¿quién eres? (habla con auth-service)
│       ├── autorizacion.js       # ¿qué puedes? (reintentos + backoff)
│       ├── proxy.js              # reenvío + cabeceras de identidad
│       ├── salud.js              # sonda agregada
│       └── errores.js            # traducción a HTTP
│
├── services/
│   ├── auth-service/             # ← copiar desde P2/backend
│   │   ├── Dockerfile
│   │   ├── docker-entrypoint.sh  # crea la tabla y arranca uvicorn
│   │   └── COPIAR-DESDE-P2.md
│   ├── authz-service/            # ← copiar desde P2/authz-service
│   │   ├── Dockerfile
│   │   └── COPIAR-DESDE-P2.md    # incluye los permisos que hay que agregar
│   │
│   ├── catalogo-service/         # GraphQL · Node.js
│   │   ├── Dockerfile
│   │   └── src/
│   │       ├── index.js
│   │       ├── esquema.js        # typeDefs
│   │       ├── resolvers.js
│   │       ├── repositorio.js    # único lugar con SQL
│   │       ├── contexto.js
│   │       └── db.js
│   │
│   ├── inventario-service/       # GraphQL · Python
│   │   ├── Dockerfile
│   │   └── app/
│   │       ├── main.py
│   │       ├── esquema_graphql.py
│   │       ├── servicio.py       # reglas, sin GraphQL ni HTTP
│   │       ├── modelos.py
│   │       ├── semilla.py
│   │       └── db.py
│   │
│   ├── pedidos-service/          # REST · Node.js
│   │   ├── Dockerfile
│   │   └── src/
│   │       ├── index.js
│   │       ├── repositorio.js
│   │       ├── catalogo.js       # comunicación directa entre servicios
│   │       ├── identidad.js
│   │       └── db.js
│   │
│   └── resenas-service/          # REST · Python
│       ├── Dockerfile
│       └── app/
│           ├── main.py
│           ├── servicio.py
│           ├── modelos.py
│           ├── esquemas.py
│           ├── identidad.py
│           └── db.py
│
├── frontend/                     # servido por el edge
│   ├── index.html                # acceso
│   ├── panel.html                # barra de servicio
│   ├── api.js, acceso.js, panel.js
│   └── estilos.css
│
├── infra/
│   ├── edge/                     # nginx: frontend + /api
│   └── postgres/init/            # crea las 5 bases
│
├── docs/
│   ├── arquitectura.md           # los tres diagramas
│   ├── guia-rapida.md            # levantar, usar, probar
│   ├── preguntas-teoricas.md
│   ├── exposicion-externa.md
│   ├── openapi-gateway.yaml      # contrato Swagger
│   └── postman_collection.json   # 28 peticiones listas
│
├── scripts/
│   ├── prueba-humo.sh
│   └── prueba-humo.ps1
│
└── k8s/                          # referencia: LoadBalancer / Ingress
```

---

## 6. Instalación y ejecución

Versión completa en **[docs/guia-rapida.md](docs/guia-rapida.md)**. Resumen:

### Requisitos previos

```bash
docker --version          # Docker Desktop con Compose v2
```

No hace falta instalar Node, Python ni PostgreSQL: todo corre en contenedores.

### Paso 1 — Traer los servicios de la Práctica 2

```bash
cp -r P2/backend/app P2/backend/requirements.txt P2/backend/scripts_init_db.py \
      P4/services/auth-service/
cp -r P2/authz-service/app P2/authz-service/requirements.txt \
      P4/services/authz-service/
```

En Windows, los comandos equivalentes están en
[services/auth-service/COPIAR-DESDE-P2.md](services/auth-service/COPIAR-DESDE-P2.md).

### Paso 2 — Agregar los permisos de la Práctica 4

En `services/authz-service/app/politicas.py`, **agregar** a la matriz
existente (los detalles están en
[services/authz-service/COPIAR-DESDE-P2.md](services/authz-service/COPIAR-DESDE-P2.md)):

```python
"admin":   {"catalogo:usar", "inventario:gestionar", "pedidos:leer",
            "pedidos:crear", "pedidos:gestionar", "resenas:leer",
            "resenas:escribir", "resenas:moderar"},
"cliente": {"catalogo:usar", "pedidos:leer", "pedidos:crear",
            "resenas:leer", "resenas:escribir"},
```

### Paso 3 — Secretos

```bash
cp .env.example .env
python -c "import secrets; print(secrets.token_urlsafe(48))"   # tres veces
```

### Paso 4 — Un solo comando

```bash
docker compose up --build
```

Abrir **http://localhost:8080**

### Paso 5 — Comprobar

```bash
curl http://localhost:8080/api/salud
bash scripts/prueba-humo.sh
```

### Puertos publicados

| Servicio | URL |
|---|---|
| Aplicación | http://localhost:8080 |
| API Gateway | http://localhost:8000/salud |
| Autenticación (Swagger) | http://localhost:8081/docs |
| Autorización (matriz) | http://localhost:8082/autorizacion/politicas |
| Catálogo (GraphQL) | http://localhost:4001/graphql |
| Inventario (GraphiQL) | http://localhost:4002/graphql |
| Pedidos | http://localhost:4003/salud |
| Reseñas (Swagger) | http://localhost:4004/docs |
| PostgreSQL | `localhost:5433` |

Todos los puertos salvo el 8080 existen únicamente para revisar cada
servicio por separado durante la calificación. En un despliegue real se
cierran: la única puerta es el edge.

---

## 7. Endpoints y contratos

Contrato completo en [docs/openapi-gateway.yaml](docs/openapi-gateway.yaml)
y en la colección de Postman ([docs/postman_collection.json](docs/postman_collection.json),
28 peticiones agrupadas por servicio).

### A través del gateway

| Método | Ruta | Permiso exigido | Servicio destino |
|---|---|---|---|
| `POST` | `/api/auth/registro` | público | auth-service |
| `POST` | `/api/auth/login` | público | auth-service |
| `GET` | `/api/auth/yo` | público* | auth-service |
| `POST` | `/api/auth/logout` | público | auth-service |
| `GET` | `/api/salud` | público | gateway |
| `GET` | `/api/diagnostico` | sesión válida | gateway → authz |
| `POST` | `/api/catalogo/graphql` | `catalogo:usar` | catalogo-service |
| `POST` | `/api/inventario/graphql` | `inventario:gestionar` | inventario-service |
| `GET` | `/api/pedidos` | `pedidos:leer` | pedidos-service |
| `POST` | `/api/pedidos` | `pedidos:crear` | pedidos-service |
| `GET` | `/api/pedidos/{id}` | `pedidos:leer` | pedidos-service |
| `PATCH` | `/api/pedidos/{id}/estado` | `pedidos:gestionar` | pedidos-service |
| `GET` | `/api/resenas` | `resenas:leer` | resenas-service |
| `POST` | `/api/resenas` | `resenas:escribir` | resenas-service |
| `GET` | `/api/resenas/resumen/{id}` | `resenas:leer` | resenas-service |
| `DELETE` | `/api/resenas/{id}` | `resenas:moderar` | resenas-service |

\* la ruta es pública en el gateway porque la propia autenticación decide si
hay sesión: devuelve `401` cuando no la hay.

### Matriz de acceso

| Permiso | Admin | Cliente |
|---|---|---|
| `catalogo:usar` | ✔ | ✔ |
| `pedidos:leer` | ✔ | ✔ |
| `pedidos:crear` | ✔ | ✔ |
| `resenas:leer` | ✔ | ✔ |
| `resenas:escribir` | ✔ | ✔ |
| `inventario:gestionar` | ✔ | ✘ |
| `pedidos:gestionar` | ✔ | ✘ |
| `resenas:moderar` | ✔ | ✘ |

### Ejemplos de GraphQL

Menú completo (catálogo):

```graphql
query {
  categorias { id nombre }
  productos(soloDisponibles: true) {
    id nombre precio
    categoria { nombre }
  }
}
```

Registrar una entrada de bodega (inventario, solo Admin):

```graphql
mutation {
  registrarMovimiento(insumoId: "1", tipo: "entrada", cantidad: 10, motivo: "compra semanal") {
    nombre existencia bajoMinimo
  }
}
```

---

## 8. Integración del módulo de autenticación

El código de la Práctica 2 **no se reescribió**. Se copió tal cual y se le
agregó un `Dockerfile` y un `docker-entrypoint.sh`. Lo que cambió es quién
lo consume: antes lo llamaba el navegador directamente, ahora lo consume el
gateway.

### Cómo verifica el gateway la sesión

```javascript
// gateway/src/sesion.js
const respuestaAuth = await fetch(`${authUrl}/auth/yo`, {
  headers: { cookie: peticion.headers.cookie },
  signal: AbortSignal.timeout(timeoutMs),
});

if (respuestaAuth.status === 401 || respuestaAuth.status === 403) return siguiente(sinSesion());

// Si el token entró en la ventana de gracia, el servicio de P2 devuelve
// una cookie nueva. Hay que reenviarla al navegador o la renovación
// automática se perdería en el camino.
const cookies = cookiesDe(respuestaAuth);
if (cookies.length > 0) respuesta.setHeader('Set-Cookie', cookies);
const renovado = respuestaAuth.headers.get('x-token-renovado');
if (renovado) respuesta.setHeader('X-Token-Renovado', renovado);
```

Esas seis líneas de reenvío de cookie son el detalle que hace que la
ventana de gracia de la Práctica 2 siga funcionando a través del gateway. Sin
ellas la renovación ocurría en el servicio de autenticación, pero el
navegador nunca recibía el token nuevo y la sesión moría igual.

### Qué se preserva

| Propiedad de la Práctica 2 | Sigue vigente porque |
|---|---|
| El token no es accesible por el usuario | La cookie sigue siendo `HttpOnly`; el gateway solo la reenvía, nunca la escribe en el cuerpo. |
| Vida y ventana de renovación configurables | `JWT_TTL_SEGUNDOS` y `JWT_GRACIA_RENOVACION_SEGUNDOS` se inyectan desde `P4/.env`. |
| Renovación automática | El gateway propaga la cookie nueva y la cabecera `X-Token-Renovado`. |
| Datos cifrados en la base | La misma tabla, ahora en `auth_db` dentro del contenedor de PostgreSQL. |
| Autorización con reintentos y backoff | Se replicó en `gateway/src/autorizacion.js` para las rutas nuevas; el servicio de autenticación conserva la suya. |

### Por qué el CORS desapareció

En la Práctica 2 el frontend corría en `:5500` y el backend en `:8000`: dos
orígenes distintos, y por eso hacía falta `ORIGENES_PERMITIDOS` y
`credentials: include`. Aquí el edge sirve el frontend y publica `/api` bajo
el **mismo origen** (`http://localhost:8080`), así que el navegador manda la
cookie sin ninguna configuración especial. Menos configuración es menos
superficie donde equivocarse.

---

## 9. Principios SOLID

Los cinco principios explicados con mis palabras y con el fragmento real del
proyecto donde se aplican.

### S — Responsabilidad única

*Una clase o módulo debe tener una sola razón para cambiar.* La prueba no es
que el archivo sea corto, sino que solo exista un motivo por el cual habría
que editarlo.

El gateway podría haber sido un solo archivo de 300 líneas. Está partido en
seis, y cada uno cambia por un motivo distinto: `sesion.js` cambia si cambia
el contrato del servicio de autenticación; `autorizacion.js`, si cambia la
política de reintentos; `rutas.js`, si se agrega un microservicio;
`proxy.js`, si cambian las cabeceras de identidad; `errores.js`, si cambia
el formato de error; `config.js`, si aparece una variable de entorno.

En el inventario la separación es aún más marcada: las reglas de negocio no
saben que existe GraphQL.

```python
# services/inventario-service/app/servicio.py
def registrar_movimiento(sesion, insumo_id, tipo, cantidad, motivo, usuario_id):
    if tipo not in TIPOS_DE_MOVIMIENTO:
        raise ErrorDeInventario(f"Tipo de movimiento invalido: {tipo}.")
    if cantidad <= 0:
        raise ErrorDeInventario("La cantidad debe ser mayor que cero.")

    insumo = sesion.get(Insumo, insumo_id)
    if insumo is None:
        raise ErrorDeInventario("Ese insumo no existe.")

    nueva_existencia = _aplicar(insumo.existencia, tipo, cantidad)
    if nueva_existencia < 0:
        raise ErrorDeInventario(...)
```

Ni un `import strawberry`, ni un `Request`, ni un código HTTP. Si mañana el
inventario expusiera REST en vez de GraphQL, este archivo no cambiaría una
línea.

### O — Abierto/cerrado

*Se debe poder agregar comportamiento sin modificar el código que ya
funciona.* Cada modificación de código probado es una oportunidad de romper
algo que ya servía.

Agregar una ruta protegida al gateway es agregar una entrada a un arreglo.
No se toca `index.js`, ni `proxy.js`, ni ninguna guarda existente:

```javascript
// gateway/src/rutas.js
{
  prefijo: '/api/pedidos',
  destino: 'pedidos',
  permisos: {
    GET: 'pedidos:leer',
    POST: 'pedidos:crear',
    PATCH: 'pedidos:gestionar',
  },
  permisoPorDefecto: 'pedidos:leer',
},
```

El código que las monta se escribió una vez y no ha vuelto a cambiar:

```javascript
// gateway/src/index.js
for (const ruta of rutas) {
  const cadena = [];
  if (!ruta.publico) {
    cadena.push(verificarSesion);
    cadena.push(exigirPermiso(verificarPermiso, resolverPermiso(ruta)));
  }
  cadena.push(crearProxy({ destino: config.servicios[ruta.destino], ... }));
  app.use(ruta.prefijo, ...cadena);
}
```

La evidencia más fuerte es histórica: los ocho permisos de la Práctica 4 se
agregaron al microservicio de autorización **editando un diccionario**. Ni el
gateway ni ningún microservicio se modificó para que la política nueva
entrara en vigor.

### L — Sustitución de Liskov

*Donde se espera un tipo, cualquier implementación suya debe funcionar sin
que quien la usa se entere.* No basta con que las firmas coincidan: el
comportamiento tiene que cumplir lo prometido.

El gateway trata a los seis servicios de negocio como intercambiables. Todos
cumplen el mismo contrato implícito —hablan HTTP, aceptan las cabeceras de
identidad, responden JSON— y por eso el mismo `crearProxy` sirve para un
servicio GraphQL en Node y para uno REST en Python:

```javascript
// gateway/src/proxy.js
export function crearProxy({ destino, prefijo, destinoBase = '', timeoutMs }) {
  return createProxyMiddleware({
    target: destino,
    pathRewrite: reescribir(prefijo, destinoBase),
    onProxyReq: (peticionProxy, peticion) => {
      if (!peticion.usuario) return;
      peticionProxy.setHeader('X-Usuario-Id', peticion.usuario.id);
      peticionProxy.setHeader('X-Usuario-Rol', peticion.usuario.rol);
      ...
```

Del lado receptor, cada servicio implementa la misma abstracción "traducir
cabeceras a una identidad", una en cada lenguaje:

```javascript
// services/pedidos-service/src/identidad.js
export function identidadDe(peticion) {
  return {
    id: peticion.headers['x-usuario-id'] ?? '',
    rol: (peticion.headers['x-usuario-rol'] ?? '').toLowerCase(),
    nombre: decodificar(peticion.headers['x-usuario-nombre']),
  };
}
```

```python
# services/resenas-service/app/identidad.py
def identidad_actual(x_usuario_id=Header(default=None), x_usuario_rol=Header(default=None), ...):
    if not x_usuario_id:
        raise HTTPException(status_code=401, detail="Falta la identidad; entra por el API Gateway.")
    return Identidad(id=x_usuario_id, rol=(x_usuario_rol or "").lower(), ...)
```

Son lenguajes distintos y el mismo contrato. Reemplazar cualquier servicio
por otro escrito en Go no obligaría a tocar el gateway.

### I — Segregación de interfaces

*Nadie debe depender de métodos que no usa.* Una interfaz gorda arrastra a
sus clientes a recompilarse por cambios que no les importan.

El gateway necesita dos cosas del módulo de la Práctica 2: saber quién es el
usuario y saber si puede. Son dos dependencias separadas, no un objeto
"servicio de seguridad" con ambos métodos:

```javascript
// gateway/src/index.js
const verificarSesion  = crearVerificadorDeSesion({ authUrl: config.servicios.auth, ... });
const verificarPermiso = crearClienteAutorizacion({ url: config.servicios.authz, ... });
```

`verificarPermiso` es una función que recibe `(rol, permiso)` y devuelve un
booleano. No conoce cookies, ni tokens, ni el usuario: solo el rol. Esa
delgadez es lo que permite que la ruta `/api/diagnostico` la reutilice para
otra cosa completamente distinta —auditar la matriz de permisos— sin
adaptadores:

```javascript
for (const permiso of permisosDeclarados()) {
  veredictos[permiso] = await verificarPermiso(peticion.usuario.rol, permiso);
}
```

El microservicio de autorización, del mismo modo, expone un único método
útil: recibe `{rol, permiso}` y responde `{permitido}`. No conoce usuarios,
ni base de datos, ni sesiones.

### D — Inversión de dependencias

*Los módulos de alto nivel no deben depender de los de bajo nivel; ambos
deben depender de abstracciones.* En la práctica: la política se decide
arriba y se inyecta hacia abajo, en lugar de quedar codificada dentro.

Ningún módulo del gateway construye sus propias dependencias. `sesion.js` no
sabe dónde vive el servicio de autenticación; lo recibe:

```javascript
// gateway/src/sesion.js
export function crearVerificadorDeSesion({ authUrl, timeoutMs }) {
  return async function verificarSesion(peticion, respuesta, siguiente) { ... };
}
```

```javascript
// gateway/src/autorizacion.js
export function crearClienteAutorizacion({ url, maxReintentos, backoffInicialMs, backoffFactor, timeoutMs }) { ... }
```

La única pieza que conoce valores concretos es `config.js`, y esos valores
salen del entorno:

```javascript
// gateway/src/config.js
export const config = {
  servicios: {
    auth: process.env.AUTH_SERVICE_URL ?? 'http://auth-service:8000',
    authz: process.env.AUTHZ_SERVICE_URL ?? 'http://authz-service:8001',
    ...
  },
  autorizacion: {
    maxReintentos: numero(process.env.AUTHZ_MAX_REINTENTOS, 4),
    backoffInicialMs: numero(process.env.AUTHZ_BACKOFF_INICIAL_MS, 200),
    ...
```

El beneficio se ve al probar: para verificar el `503` por caída del servicio
de autorización basta con levantar el gateway apuntando `AUTHZ_SERVICE_URL`
a un puerto muerto, sin modificar una línea de código. Y en el inventario, la
misma idea con la base de datos: `servicio.py` recibe una `Session` por
parámetro y nunca la crea.

### Otras prácticas de código limpio

Nombres descriptivos en español sin abreviaturas; ninguna función supera las
30 líneas; tipado completo en los servicios Python; sin números mágicos (los
tiempos y las URL vienen del entorno, los estados de listas con nombre);
manejo de errores centralizado en cada servicio; y comentarios que explican
**por qué** se tomó una decisión, no qué hace la línea siguiente.

---

## 10. Evidencia de pruebas

### 10.1 Prueba de humo automatizada

```bash
docker compose up --build -d
bash scripts/prueba-humo.sh
```

Recorre 18 comprobaciones sobre el sistema levantado:

| # | Escenario | Esperado |
|---|---|---|
| 1 | `GET /api/salud` con todo arriba | `200`, seis servicios `arriba` |
| 2 | Registro de Admin | `201` + cookie `HttpOnly` |
| 3 | Registro de Cliente | `201` |
| 4 | El token no aparece en el cuerpo de la respuesta | ausente |
| 5 | Catálogo GraphQL sin cookie | `401` |
| 6 | Catálogo GraphQL con Admin | `200` |
| 7 | Catálogo GraphQL con Cliente | `200` |
| 8 | Inventario GraphQL con Admin | `200` |
| 9 | Inventario GraphQL con Cliente | `403` |
| 10 | Cliente crea un pedido | `201`, total calculado desde el catálogo |
| 11 | Cliente lista sus pedidos | `200`, solo los suyos |
| 12 | Admin cambia el estado de un pedido | `200` |
| 13 | Cliente intenta cambiar el estado | `403` |
| 14 | Cliente publica una reseña | `201` |
| 15 | Segunda reseña del mismo producto | `409` |
| 16 | Calificación fuera de 1..5 | `422` |
| 17 | Resumen de calificaciones | `200` |
| 18 | Diagnóstico de permisos del rol | mapa permiso → veredicto |

Salida esperada al final:

```text
== Resultado
  Todas las comprobaciones pasaron.
```

### 10.2 Verificación del retry loop y del 503

```bash
docker compose stop authz-service
curl -i -b cookies.txt http://localhost:8080/api/pedidos
```

En el log del gateway:

```text
[gateway] autorizacion sin respuesta (intento 1/4).
[gateway] reintentando en 0.20 s.
[gateway] autorizacion sin respuesta (intento 2/4).
[gateway] reintentando en 0.40 s.
[gateway] autorizacion sin respuesta (intento 3/4).
[gateway] reintentando en 0.80 s.
[gateway] autorizacion agoto 4 intentos para rol=cliente permiso=pedidos:leer.
[gateway] GET /api/pedidos -> 503 (1412 ms)
```

Respuesta al cliente:

```json
{"detalle":"El servicio de autorizacion no respondio tras 4 intentos.",
 "codigo":"AUTORIZACION_NO_DISPONIBLE"}
```

El código es `503` y no `403`: el acceso no se denegó por falta de permisos.

### 10.3 Verificación de la renovación del token heredada de P2

Con `JWT_TTL_SEGUNDOS=20` y `JWT_GRACIA_RENOVACION_SEGUNDOS=60`, esperar 25
segundos y pulsar cualquier pantalla:

```text
< HTTP/1.1 200 OK
< X-Token-Renovado: true
< Set-Cookie: acceso_token=eyJhbGciOi...; HttpOnly; Path=/
```

La tira de comanda del frontend lo imprime como *token renovado* junto a la
línea correspondiente.

### 10.4 Verificación de la separación de bases de datos

```bash
docker compose exec postgres psql -U aroma -l
```

Aparecen `auth_db`, `catalogo_db`, `inventario_db`, `pedidos_db` y
`resenas_db`. Ninguna tabla tiene una llave foránea que cruce de una a otra:
las referencias entre servicios son identificadores sueltos que se resuelven
por API.

### 10.5 Verificación de los contratos

- Swagger del servicio de autenticación: http://localhost:8081/docs
- Swagger de reseñas: http://localhost:4004/docs
- Sandbox de GraphQL del catálogo: http://localhost:4001/graphql
- GraphiQL del inventario: http://localhost:4002/graphql
- Colección de Postman: `docs/postman_collection.json` (28 peticiones)

---

## 11. Documentación de prompts de IA

Se utilizó Claude (Anthropic) como apoyo, avanzando por incrementos
verificables. Cada prompt siguió la estructura
**rol → contexto → restricciones → alcance acotado → autorrevisión**.

---

### Prompt 1 — Reparto de responsabilidades entre servicios (sin código)

```text
Actúa como arquitecto de software especializado en sistemas distribuidos.

Contexto: debo construir un sistema de temática libre con al menos 4
microservicios, un API Gateway, Docker Compose, dos lenguajes y GraphQL en
al menos dos servicios. Debo integrar sin reescribirlo el módulo de
autenticación que ya construí: JWT en cookie HTTP-only, ventana de gracia
para renovación y un microservicio de autorización aparte que se consulta
con reintentos y backoff.

Tarea (solo esta):
1. Propón un reparto de 4 microservicios para una cafetería, indicando qué
   datos posee cada uno y cuáles NO debe poseer.
2. Decide dónde debe vivir la verificación del token: en el gateway o en el
   servicio de autenticación. Argumenta con las consecuencias de cada
   opción.
3. Señala qué partes de mi integración podrían romper el comportamiento del
   módulo de autenticación sin que se note en una prueba rápida.

NO escribas código todavía.
```

**Respuesta obtenida:** propuso catálogo, inventario, pedidos y reseñas con
base de datos separada. Recomendó que el gateway **no** verifique el JWT
sino que delegue en `/auth/yo`, porque duplicar la lógica de la ventana de
gracia produciría dos implementaciones divergentes. En el punto 3 advirtió
que el gateway debía reenviar el `Set-Cookie` de la renovación.

**Análisis crítico y ajustes aplicados:**

- Acepté la delegación en `/auth/yo`. El costo es un salto de red extra por
  petición; el beneficio es que el secreto del JWT vive en un solo lugar.
- Acepté la advertencia sobre el `Set-Cookie` y la convertí en la primera
  prueba que escribí, porque es un fallo silencioso: todo funciona hasta que
  el token entra en la ventana de gracia, tres minutos después.
- **Rechacé** su sugerencia de un servicio de notificaciones como cuarto
  microservicio. Sin destinatario real habría sido un `console.log` con
  Dockerfile. Preferí reseñas, que tiene reglas propias verificables (una
  por persona y producto, promedios).
- **Detecté un vacío:** la propuesta no decía cómo obtiene pedidos el precio
  de un producto. Resolví que lo consulte al catálogo en el momento de crear
  el pedido, pero que copie el precio en `pedido_items` para conservar el
  histórico. Es la distinción entre dato de referencia y dato histórico, y
  no estaba en la respuesta.

---

### Prompt 2 — Gateway: sesión, permisos y reenvío

```text
Implementa ÚNICAMENTE el middleware de sesión y el cliente de autorización
del API Gateway (Node.js, Express, ESM, sin TypeScript).

Requisitos:
- La sesión se verifica llamando a GET /auth/yo del servicio de
  autenticación, reenviando la cookie del cliente.
- Si esa respuesta trae Set-Cookie (renovación dentro de la ventana de
  gracia), hay que reenviarla al navegador junto con X-Token-Renovado.
- El cliente de autorización consulta POST /autorizacion/verificar con
  reintentos y backoff exponencial configurables.

Restricciones obligatorias:
- Distingue "sin permiso" (definitivo, 403) de "sin respuesta"
  (transitorio, reintentar, y al agotar → 503). Un fallo de red NUNCA debe
  traducirse en 403.
- Timeout explícito en cada llamada saliente.
- Configuración por parámetros de constructor, no leída de variables
  globales.

Después de escribirlo, dime qué pasa si /auth/yo devuelve 200 con un JSON
cuyos campos se llaman distinto de los que asumes.
```

**Respuesta obtenida:** entregó ambos módulos con la separación de fallos
correcta. En la autorrevisión reconoció que asumía campos `id` y `rol` y que
un contrato distinto produciría un usuario con campos vacíos que llegarían
como cabeceras vacías a los microservicios.

**Análisis crítico y ajustes aplicados:**

- **Corrección aplicada por mí:** ese fallo era peor de lo que admitía. Con
  `rol` vacío, la consulta de autorización habría preguntado por el permiso
  de un rol inexistente y devuelto `403` en todas partes, lo que parece un
  problema de permisos y no de contrato. Escribí `normalizarSesion` con una
  lista de nombres candidatos y, sobre todo, hice que un `id` o un `rol`
  vacíos produzcan un `502` con el código `SESION_ILEGIBLE` y un mensaje que
  dice exactamente qué archivo editar. Un error de integración debe
  anunciarse, no disfrazarse de otra cosa.
- **Corrección aplicada por mí:** el borrador esperaba el backoff también
  después del último intento, retrasando el `503` sin ninguna utilidad.
  Moví la espera dentro de `if (intento < maxReintentos)`.
- **Corrección de robustez:** no contemplaba que el servicio de autorización
  respondiera `200` con un cuerpo no interpretable. Añadí ese caso al camino
  transitorio, junto con los `5xx`.
- **Rechacé** su propuesta de cachear el veredicto de autorización durante
  unos segundos. Aceleraría, pero un permiso revocado seguiría vigente
  mientras durara la caché, y el enunciado pide que la autorización sea
  siempre externa y consultada. Queda anotado como mejora si el volumen lo
  exigiera.

---

### Prompt 3 — GraphQL en dos lenguajes

```text
Implementa el esquema GraphQL del servicio de catálogo (Node.js, Apollo
Server 4) y el del inventario (Python, Strawberry).

Restricciones:
- Las mutaciones solo pueden ejecutarlas usuarios con rol Admin. El rol
  llega en la cabecera X-Usuario-Rol que inyecta el gateway; el servicio no
  abre tokens.
- Las reglas de negocio del inventario (no dejar existencias negativas,
  tipos de movimiento válidos) deben vivir en un módulo que no importe
  Strawberry ni FastAPI.
- Consultas parametrizadas siempre.

Explícame después cómo controlo permisos de lectura y escritura por
separado si GraphQL expone un único endpoint, y qué implica eso para el
gateway.
```

**Respuesta obtenida:** ambos esquemas, con las reglas del inventario
aisladas en `servicio.py`. En la autorrevisión explicó que el gateway solo
puede conceder permisos de grano grueso por endpoint, porque `query` y
`mutation` viajan por la misma URL y el mismo método, y que la distinción
fina tiene que hacerse en el resolver.

**Análisis crítico y ajustes aplicados:**

- Acepté el modelo de dos niveles y lo documenté como decisión explícita en
  las preguntas teóricas: `catalogo:usar` en el gateway, rol Admin en el
  resolver. Es una diferencia real con REST que conviene poder explicar.
- **Corrección aplicada por mí:** en el borrador del inventario, la
  comprobación del rol estaba escrita dentro de cada mutación. La extraje a
  `_exigir_admin(info)` para no repetirla, siguiendo la misma idea de fábrica
  de guardas que uso en el gateway.
- **Detecté un problema de diseño:** la mutación de ajuste trataba la
  cantidad como un incremento, igual que una entrada. Un ajuste de
  inventario es el resultado de un conteo físico: la cantidad **es** la
  existencia real, no algo que se suma. Cambié `_aplicar` en consecuencia.
- Señalé el N+1 de `Producto.categoria` y decidí **no** resolverlo con un
  `DataLoader`: con tres categorías y diez productos añadiría complejidad
  sin beneficio medible. Quedó documentado como pregunta teórica en vez de
  como código innecesario.

---

### Prompt 4 — Revisión de la orquestación

```text
Actúa como revisor. Te comparto docker-compose.yml, los ocho Dockerfile y
la configuración de nginx.

No reescribas el proyecto. Entrégame:
1. Tabla de hallazgos: severidad, archivo y el cambio mínimo que lo corrige.
2. Puntos donde el sistema podría quedar arriba pero inservible (un servicio
   que responde antes de estar listo, una dependencia que arranca tarde).
3. Falsos positivos: cosas que parecen problemas pero no lo son aquí, con su
   justificación.
```

**Respuesta obtenida:**

| Severidad | Hallazgo |
|---|---|
| Alta | `depends_on` sin `condition: service_healthy`: los servicios arrancaban antes de que PostgreSQL aceptara conexiones. |
| Media | Sin `.dockerignore`, los `.venv/` y `node_modules/` locales entraban en las imágenes. |
| Media | El `docker-entrypoint.sh` fallaría en Windows por saltos de línea CRLF. |
| Baja | Sugerencia de fijar versiones exactas en todas las dependencias. |

**Análisis crítico y ajustes aplicados:**

- **Aceptado (alta):** añadí `healthcheck` a PostgreSQL y
  `condition: service_healthy` en quienes dependen de él. Pero **no me
  quedé ahí**: cada servicio reintenta además la conexión por su cuenta
  (`esperarBaseDeDatos`, `esperar_base_de_datos`). Un healthcheck dice que
  el puerto responde, no que la base concreta exista.
- **Aceptado (media):** agregué `.dockerignore` a cada servicio. Además del
  peso, un `.env` dentro de una imagen es una filtración de secretos.
- **Aceptado (media):** el hallazgo del CRLF era correcto y difícil de
  diagnosticar —el error es `no such file or directory` sobre un archivo que
  claramente existe—. Añadí `.gitattributes` con `*.sh text eol=lf` y lo
  documenté en la tabla de errores frecuentes.
- **Rechazado con justificación (baja):** no fijé versiones exactas. Con
  rangos, `npm install` y `pip install` resuelven parches de seguridad al
  reconstruir. En un producto en producción usaría lockfiles; para una
  práctica que se califica una vez, el riesgo de que una versión exacta ya
  no exista en el registro es mayor.
- **Falso positivo señalado correctamente:** marcó como riesgo que los
  microservicios confíen en las cabeceras `X-Usuario-Rol`. Es correcto en
  general, pero aquí solo el edge tiene puerto público en un despliegue
  real. Aun así reforcé los dos puntos críticos —mutaciones de inventario y
  borrado de reseñas— con una comprobación propia del rol.

---

### Hallazgo adicional durante las pruebas

La primera ejecución de `prueba-humo.sh` devolvió `403` en las quince
comprobaciones que requerían un permiso. La causa no era el gateway ni la
prueba: la matriz de `politicas.py` seguía teniendo solo `ruta1:leer` y
`ruta2:leer`, los permisos de la Práctica 2.

El episodio resultó útil por dos motivos. Primero, confirmó que el sistema
se comporta exactamente como debe: si un permiso no existe en la matriz, se
deniega, y ningún servicio lo concede por su cuenta. Segundo, dejó claro que
el fallo era difícil de diagnosticar desde fuera —un `403` no dice qué
permiso faltó—. Por eso agregué la ruta `GET /api/diagnostico`, que pregunta
al microservicio de autorización por cada permiso declarado y devuelve el
veredicto uno por uno, y la pestaña **Sistema** del frontend que lo muestra.

Es la única funcionalidad del proyecto que nació de una falla propia.

---

### Conclusión sobre el uso de IA

La herramienta aceleró la escritura y anticipó dos problemas reales: el
reenvío del `Set-Cookie` de la renovación, que habría roto en silencio una
funcionalidad de la Práctica 2, y el arranque de los servicios antes de que
PostgreSQL estuviera listo.

Pero produjo también cuatro defectos que solo aparecieron al revisar: la
espera inútil después del último reintento, el manejo ausente de respuestas
no interpretables, la comprobación de rol repetida en cada mutación, y una
mutación de ajuste de inventario que sumaba cuando debía sustituir. A eso se
suma un vacío de diseño —de dónde sale el precio de un pedido y por qué
conviene copiarlo— que no señaló y que era necesario resolver para que el
histórico de pedidos tuviera sentido.

El patrón se repitió respecto de las prácticas anteriores: el código
generado es correcto en el camino feliz y frágil en los bordes, y sobre todo
**no distingue entre lo que es correcto y lo que es correcto para este
dominio**. La mutación de ajuste compilaba, pasaba una prueba y estaba mal:
solo alguien que sepa cómo se cuenta un inventario podía verlo. Los prompts
más útiles siguieron siendo los que exigen a la herramienta auditar su
propio resultado con una pregunta concreta, porque obligan a explicitar
supuestos que de otro modo quedan enterrados en el código.

---

## Autor

**Nombre:** Jennifer Yulissa Lourdes Taperio Manuel

**Carné:** 202103763

**Sección:** B

**Curso:** Software Avanzado — Segundo Semestre 2026
