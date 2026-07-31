# API REST de Solicitudes Operativas

Práctica 1: Software Avanzado, Segundo Semestre 2026
Universidad de San Carlos de Guatemala · Facultad de Ingeniería · Ingeniería en Ciencias y Sistemas

API REST para gestionar las solicitudes operativas de una academia ficticia, construida aplicando los cinco principios SOLID, prácticas de código limpio y persistencia en PostgreSQL.

---

## Índice

1. [Stack tecnológico](#1-stack-tecnológico)
2. [Estructura del proyecto](#2-estructura-del-proyecto)
3. [Instalación paso a paso](#3-instalación-paso-a-paso)
4. [Configuración de la base de datos](#4-configuración-de-la-base-de-datos)
5. [Ejecución y pruebas](#5-ejecución-y-pruebas)
6. [Endpoints de la API](#6-endpoints-de-la-api)
7. [Principios SOLID aplicados](#7-principios-solid-aplicados)
8. [Prácticas de código limpio](#8-prácticas-de-código-limpio)
9. [Seguridad del código](#9-seguridad-del-código)
10. [Evidencia de pruebas](#10-evidencia-de-pruebas)
11. [Documentación de prompts de IA](#11-documentación-de-prompts-de-ia)

---

## 1. Stack tecnológico

| Componente | Tecnología | Por qué se eligió |
|---|---|---|
| Lenguaje | Python 3.11+ | Sintaxis breve y tipado opcional; menos ceremonia que TypeScript para un proyecto de este tamaño. |
| Framework | FastAPI | Genera documentación interactiva automáticamente e inyecta dependencias de forma nativa, lo que facilita aplicar el principio de inversión de dependencias. |
| Servidor | Uvicorn | Servidor ASGI con recarga automática durante el desarrollo. |
| ORM | SQLAlchemy 2.0 | Consultas parametrizadas por diseño y mapeo tipado con `Mapped[...]`. |
| Driver | psycopg 3 | Driver oficial de PostgreSQL para Python. |
| Validación | Pydantic 2 | Valida los datos de entrada antes de que lleguen a la lógica de negocio. |
| Configuración | pydantic-settings | Carga y valida las variables de entorno al arrancar. |
| Calidad | Ruff | Linter y formateador en una sola herramienta. |
| Pruebas | pytest | Pruebas del servicio sin depender de la base de datos. |

> **Nota sobre la elección del lenguaje:** la práctica permite JavaScript/TypeScript o Python. Se eligió Python porque no requiere un paso de compilación ni configuración de `tsconfig.json`, y porque FastAPI expone Swagger UI en `/docs` sin instalar nada adicional, lo que reduce el tiempo necesario para probar cada endpoint.

---

## 2. Estructura del proyecto

La organización sigue una arquitectura por capas: cada carpeta tiene una única razón para cambiar.

```text
P1/
├── app/
│   ├── main.py                        # Punto de entrada (application factory)
│   ├── core/
│   │   ├── config.py                  # Variables de entorno validadas
│   │   └── database.py                # Engine y sesión de SQLAlchemy
│   ├── domain/                        # Núcleo: no depende de nada externo
│   │   ├── entities.py                # Entidad SolicitudOperativa
│   │   ├── policies.py                # Reglas de transición de estado
│   │   ├── repositories.py            # Interfaces (contratos) de persistencia
│   │   └── exceptions.py              # Errores de negocio
│   ├── infrastructure/                # Detalles reemplazables
│   │   ├── models.py                  # Modelo ORM (tabla física)
│   │   ├── postgres_repository.py     # Implementación con PostgreSQL
│   │   └── memory_repository.py       # Implementación en memoria (pruebas)
│   ├── services/
│   │   └── solicitud_service.py       # Casos de uso
│   ├── schemas/
│   │   └── solicitud.py               # Validación de entrada/salida
│   └── api/
│       ├── deps.py                    # Inyección de dependencias
│       ├── errors.py                  # Traducción de errores a HTTP
│       └── routes/solicitudes.py      # Endpoints REST
├── sql/schema.sql                     # Creación del esquema
├── tests/                             # Pruebas automatizadas
├── docs/api.http                      # Requests de prueba para VS Code
├── scripts_init_db.py                 # Crea las tablas desde Python
├── requirements.txt
├── pyproject.toml                     # Configuración de Ruff y pytest
├── .env.example
└── .gitignore
```

La dirección de las dependencias siempre apunta hacia adentro: `api → services → domain`. La carpeta `infrastructure` implementa los contratos que define `domain`, nunca al revés.

---

## 3. Instalación paso a paso

### 3.1 Requisitos previos

Verificar las versiones instaladas:

```bash
python --version   # se requiere 3.11 o superior (probado en 3.11.4)
git --version
code --version
```

Si Python no está instalado o es menor a 3.11, descargarlo desde [python.org](https://www.python.org/downloads/). En Windows, marcar la casilla **Add Python to PATH** durante la instalación.

### 3.2 Extensiones recomendadas de VS Code

| Extensión | Uso |
|---|---|
| Python (Microsoft) | Autocompletado y depuración. |
| Ruff (Astral Software) | Muestra los errores de estilo mientras se escribe. |
| REST Client (Huachao Mao) | Ejecuta el archivo `docs/api.http` sin salir del editor. |

### 3.3 Entorno virtual e instalación de dependencias

Desde la carpeta `P1` del repositorio:

```bash
# 1. Crear el entorno virtual
python -m venv .venv

# 2. Activarlo
#    Windows (PowerShell):
.venv\Scripts\Activate.ps1
#    Linux / macOS:
source .venv/bin/activate

# 3. Instalar las dependencias
pip install -r requirements.txt
```

Si PowerShell bloquea la activación, ejecutar una sola vez:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### 3.4 Variables de entorno

```bash
# Windows
copy .env.example .env
# Linux / macOS
cp .env.example .env
```

Luego editar `.env` y colocar la cadena de conexión real. **El archivo `.env` está listado en `.gitignore` y no debe subirse nunca al repositorio.**

---

## 4. Configuración de la base de datos

### Opción recomendada: Neon (PostgreSQL gestionado, plan gratuito)

1. Crear una cuenta en [neon.tech](https://neon.tech) e iniciar un proyecto nuevo.
2. Copiar la cadena de conexión que ofrece el panel.
3. Adaptarla al driver `psycopg` cambiando el prefijo `postgresql://` por `postgresql+psycopg://` y pegarla en `.env`:

```env
DATABASE_URL=postgresql+psycopg://usuario:contrasena@ep-xxx.us-east-2.aws.neon.tech/neondb?sslmode=require
```

### Alternativa: Supabase

En el panel: **Project Settings → Database → Connection string → URI**. Aplicar el mismo cambio de prefijo.

### Alternativa: PostgreSQL local

```bash
createdb solicitudes_db
```

```env
DATABASE_URL=postgresql+psycopg://postgres:tu_password@localhost:5432/solicitudes_db
```

### Crear la tabla

Cualquiera de las dos opciones funciona:

```bash
# Opción A: desde Python, usando los modelos ORM
python scripts_init_db.py
```

```sql
-- Opción B: pegar el contenido de sql/schema.sql en el editor SQL de Neon o Supabase
```

---

## 5. Ejecución y pruebas

```bash
# Levantar el servidor con recarga automática
uvicorn app.main:app --reload
```

| Recurso | URL |
|---|---|
| Documentación interactiva (Swagger) | http://127.0.0.1:8000/docs |
| Documentación alternativa (ReDoc) | http://127.0.0.1:8000/redoc |
| Verificación de estado | http://127.0.0.1:8000/salud |

La forma más rápida de probar los endpoints es entrar a `/docs` y usar el botón **Try it out** de cada operación. Como alternativa, el archivo `docs/api.http` contiene las peticiones listas para ejecutarse con la extensión REST Client.

```bash
# Ejecutar las pruebas automatizadas
pytest -q

# Revisar estilo y errores comunes
ruff check .
ruff format .
```

Resultado esperado de la suite:

```text
5 passed
```

---

## 6. Endpoints de la API

Prefijo base: `/api/v1/solicitudes`

| Método | Ruta | Descripción | Éxito | Errores |
|---|---|---|---|---|
| `GET` | `/` | Lista todas las solicitudes. | `200` | — |
| `GET` | `/{id}` | Obtiene una solicitud por su id. | `200` | `404` |
| `POST` | `/` | Registra una nueva solicitud. | `201` | `422` |
| `PUT` | `/{id}` | Reemplaza todos los atributos. | `200` | `404`, `422` |
| `PATCH` | `/{id}/estado` | Actualiza **únicamente** el estado. | `200` | `404`, `409`, `422` |
| `DELETE` | `/{id}` | Elimina la solicitud. | `204` | `404` |

Decisiones de diseño REST:

- El recurso se nombra en plural y sin verbos en la URL; la acción la determina el método HTTP.
- `PUT` reemplaza el recurso completo, mientras que `PATCH` modifica una sola propiedad. Por eso el estado tiene su propia subruta `/{id}/estado`: describe con precisión qué se está modificando.
- `DELETE` responde `204 No Content` porque no hay cuerpo que devolver.
- El versionado `/api/v1` permite publicar una versión 2 en el futuro sin romper a los clientes existentes.

### Ejemplo de uso

```bash
# Registrar
curl -X POST http://127.0.0.1:8000/api/v1/solicitudes \
  -H "Content-Type: application/json" \
  -d '{
    "titulo": "Adquisición de nuevo servidor",
    "area_solicitante": "Infraestructura TI",
    "prioridad": 3,
    "costo_estimado": 2500.00,
    "estado": "registrada"
  }'
```

```json
{
  "id": "f72a6138-48dc-4635-b682-4d14fb3e98b9",
  "titulo": "Adquisición de nuevo servidor",
  "area_solicitante": "Infraestructura TI",
  "prioridad": 3,
  "costo_estimado": "2500.00",
  "estado": "registrada"
}
```

```bash
# Cambiar solo el estado
curl -X PATCH http://127.0.0.1:8000/api/v1/solicitudes/f72a6138-48dc-4635-b682-4d14fb3e98b9/estado \
  -H "Content-Type: application/json" \
  -d '{"estado": "en_proceso"}'
```

Los montos se devuelven como texto con dos decimales. Es una decisión deliberada: al convertir dinero a `float` se pierde precisión por la representación binaria del punto flotante, y en un sistema que maneja costos eso produce descuadres.

---

## 7. Principios SOLID aplicados

Los cinco principios se explican a continuación con mis propias palabras y con fragmentos reales del código de este proyecto.

### 7.1 S — Principio de Responsabilidad Única (SRP)

**Qué significa:** una clase debe tener una sola razón para cambiar. Si al modificar la forma de guardar los datos también hay que tocar la validación y la respuesta HTTP, esa clase tiene demasiadas responsabilidades.

**Cómo se aplica aquí:** cada operación pasa por cuatro objetos distintos y cada uno hace una sola cosa.

| Archivo | Única responsabilidad |
|---|---|
| `app/schemas/solicitud.py` | Validar el formato de los datos que entran y salen. |
| `app/services/solicitud_service.py` | Ejecutar las reglas de negocio. |
| `app/infrastructure/postgres_repository.py` | Leer y escribir en PostgreSQL. |
| `app/api/routes/solicitudes.py` | Traducir HTTP a llamadas del servicio. |

El endpoint es la evidencia más clara: no valida, no consulta la base de datos y no maneja errores. Solo delega.

```python
# app/api/routes/solicitudes.py
@router.patch("/{solicitud_id}/estado", response_model=SolicitudRespuesta)
def actualizar_estado(
    solicitud_id: UUID,
    datos: EstadoActualizar,
    servicio: ServicioSolicitudesDep,
) -> SolicitudRespuesta:
    """Actualiza exclusivamente el estado de una solicitud."""
    return servicio.cambiar_estado(solicitud_id, datos.estado)
```

La validación vive completa en el esquema, separada del resto:

```python
# app/schemas/solicitud.py
class SolicitudBase(BaseModel):
    """Campos compartidos por las operaciones de escritura."""

    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    titulo: str = Field(min_length=3, max_length=120)
    area_solicitante: str = Field(min_length=3, max_length=80)
    prioridad: int = Field(ge=1, le=5)
    costo_estimado: Decimal = Field(ge=0, max_digits=12, decimal_places=2)
    estado: EstadoSolicitud = EstadoSolicitud.REGISTRADA
```

### 7.2 O — Principio Abierto/Cerrado (OCP)

**Qué significa:** el código debe permitir agregar comportamiento nuevo sin modificar el que ya funciona y está probado. Se extiende, no se edita.

**Cómo se aplica aquí:** las reglas de cambio de estado están detrás de una abstracción. Si mañana la academia decide que una solicitud finalizada puede reabrirse, se escribe una clase nueva; `ServicioSolicitudes` no se toca.

```python
# app/domain/policies.py
class PoliticaTransicionEstado(ABC):
    """Contrato de una política de transición de estados."""

    @abstractmethod
    def es_permitida(self, actual: EstadoSolicitud, nuevo: EstadoSolicitud) -> bool:
        """Indica si se puede pasar de `actual` a `nuevo`."""


class TransicionSecuencial(PoliticaTransicionEstado):
    """Política por defecto: el flujo avanza y no retrocede.

    registrada -> en_proceso -> finalizada
    """

    _TRANSICIONES_VALIDAS: dict[EstadoSolicitud, frozenset[EstadoSolicitud]] = {
        EstadoSolicitud.REGISTRADA: frozenset(
            {EstadoSolicitud.EN_PROCESO, EstadoSolicitud.FINALIZADA}
        ),
        EstadoSolicitud.EN_PROCESO: frozenset({EstadoSolicitud.FINALIZADA}),
        EstadoSolicitud.FINALIZADA: frozenset(),
    }

    def es_permitida(self, actual: EstadoSolicitud, nuevo: EstadoSolicitud) -> bool:
        if actual == nuevo:
            return True  # operación idempotente
        return nuevo in self._TRANSICIONES_VALIDAS[actual]
```

Nótese que las reglas viven en un diccionario y no en una cadena de `if/elif`. Agregar un estado nuevo es agregar una entrada, no reescribir un condicional.

### 7.3 L — Principio de Sustitución de Liskov (LSP)

**Qué significa:** cualquier implementación de una interfaz debe poder usarse en lugar de otra sin que el código que la consume se entere ni se rompa.

**Cómo se aplica aquí:** existen dos repositorios que cumplen el mismo contrato. `RepositorioSolicitudesPostgres` guarda en la base de datos; `RepositorioSolicitudesMemoria` guarda en un diccionario. Ambos respetan las mismas reglas: devolver `None` cuando el registro no existe, devolver la entidad cuando sí, y no lanzar excepciones propias.

```python
# app/infrastructure/memory_repository.py
class RepositorioSolicitudesMemoria(RepositorioSolicitudes):
    """Almacena las solicitudes en un diccionario en memoria."""

    def cambiar_estado(
        self, solicitud_id: UUID, estado: EstadoSolicitud
    ) -> SolicitudOperativa | None:
        solicitud = self._datos.get(solicitud_id)
        if solicitud is None:
            return None

        actualizada = solicitud.con_estado(estado)
        self._datos[solicitud_id] = actualizada
        return actualizada
```

**Evidencia comprobable:** la suite de `tests/` ejercita `ServicioSolicitudes` con el repositorio en memoria. El servicio fue escrito para PostgreSQL y funciona sin un solo cambio, lo que demuestra que la sustitución es real y no solo teórica.

```python
# tests/test_solicitud_service.py
@pytest.fixture
def servicio() -> ServicioSolicitudes:
    return ServicioSolicitudes(RepositorioSolicitudesMemoria(), TransicionSecuencial())
```

### 7.4 I — Principio de Segregación de Interfaces (ISP)

**Qué significa:** es preferible tener varias interfaces pequeñas y específicas que una grande que obligue a implementar métodos que no se usan.

**Cómo se aplica aquí:** en lugar de una interfaz única con seis métodos, el contrato se dividió en lectura y escritura. Un futuro módulo de reportes podrá depender solo de `LectorSolicitudes` y quedará imposibilitado de escribir por diseño.

```python
# app/domain/repositories.py
class LectorSolicitudes(ABC):
    """Operaciones de solo lectura."""

    @abstractmethod
    def listar(self) -> list[SolicitudOperativa]:
        """Devuelve todas las solicitudes registradas."""

    @abstractmethod
    def obtener_por_id(self, solicitud_id: UUID) -> SolicitudOperativa | None:
        """Devuelve una solicitud o `None` si no existe."""


class EscritorSolicitudes(ABC):
    """Operaciones de escritura."""

    @abstractmethod
    def crear(self, solicitud: SolicitudOperativa) -> SolicitudOperativa:
        """Persiste una solicitud nueva."""

    @abstractmethod
    def cambiar_estado(
        self, solicitud_id: UUID, estado: EstadoSolicitud
    ) -> SolicitudOperativa | None:
        """Actualiza únicamente el estado, sin tocar el resto de campos."""


class RepositorioSolicitudes(LectorSolicitudes, EscritorSolicitudes, ABC):
    """Repositorio completo: composición de los dos contratos anteriores."""
```

El método `cambiar_estado` también responde a este principio: existe porque el requerimiento de actualizar solo el estado merece una operación propia y estrecha, en lugar de reutilizar `reemplazar` y arriesgarse a sobrescribir campos por accidente.

### 7.5 D — Principio de Inversión de Dependencias (DIP)

**Qué significa:** los módulos de alto nivel (las reglas de negocio) no deben depender de los de bajo nivel (la base de datos). Ambos deben depender de abstracciones.

**Cómo se aplica aquí:** `ServicioSolicitudes` recibe sus dependencias ya construidas y solo conoce los tipos abstractos. No importa SQLAlchemy en ningún punto.

```python
# app/services/solicitud_service.py
class ServicioSolicitudes:
    """Orquesta las operaciones sobre solicitudes operativas."""

    def __init__(
        self,
        repositorio: RepositorioSolicitudes,
        politica_estado: PoliticaTransicionEstado,
    ) -> None:
        self._repositorio = repositorio
        self._politica_estado = politica_estado

    def cambiar_estado(
        self, solicitud_id: UUID, nuevo_estado: EstadoSolicitud
    ) -> SolicitudOperativa:
        actual = self.obtener(solicitud_id)
        if not self._politica_estado.es_permitida(actual.estado, nuevo_estado):
            raise TransicionEstadoInvalidaError(actual.estado, nuevo_estado)

        resultado = self._repositorio.cambiar_estado(solicitud_id, nuevo_estado)
        if resultado is None:
            raise SolicitudNoEncontradaError(solicitud_id)
        return resultado
```

La unión entre abstracción e implementación ocurre en un solo archivo, que funciona como raíz de composición:

```python
# app/api/deps.py
def obtener_repositorio(session: SesionBD) -> RepositorioSolicitudes:
    """Devuelve la implementación de repositorio en uso."""
    return RepositorioSolicitudesPostgres(session)


def obtener_servicio(
    repositorio: Annotated[RepositorioSolicitudes, Depends(obtener_repositorio)],
    politica: Annotated[PoliticaTransicionEstado, Depends(obtener_politica_estado)],
) -> ServicioSolicitudes:
    """Arma el servicio con sus dependencias ya resueltas."""
    return ServicioSolicitudes(repositorio, politica)
```

Migrar a MongoDB implicaría escribir un repositorio nuevo y cambiar una línea de este archivo. El dominio y el servicio quedarían intactos.

---

## 8. Prácticas de código limpio

| Práctica | Cómo se refleja en el proyecto |
|---|---|
| Nombres descriptivos | `cambiar_estado`, `PoliticaTransicionEstado`, `costo_estimado`. No hay variables de una letra ni abreviaturas ambiguas. |
| Funciones cortas | Ninguna función supera las 20 líneas; la mayoría tiene menos de 10. |
| Sin duplicación (DRY) | `SolicitudCrear` y `SolicitudReemplazar` heredan de `SolicitudBase` en lugar de repetir los cinco campos y sus validaciones. |
| Sin números mágicos | Los estados están en el enumerado `EstadoSolicitud`; el redondeo usa la constante `DOS_DECIMALES`. |
| Manejo de errores centralizado | No hay `try/except` repetidos en los endpoints: `app/api/errors.py` traduce cada excepción de dominio a su código HTTP. |
| Comentarios que explican el porqué | Los comentarios justifican decisiones (por qué `Decimal` y no `float`), no describen lo que el código ya dice. |
| Tipado explícito | Todas las firmas están anotadas, lo que permite detectar errores antes de ejecutar. |
| Estilo automatizado | `ruff check .` y `ruff format .` pasan sin advertencias. |

---

## 9. Seguridad del código

| Riesgo (OWASP Top 10) | Mitigación implementada |
|---|---|
| A03 — Inyección SQL | Todas las consultas usan el lenguaje de expresiones de SQLAlchemy, que envía los valores como parámetros ligados. No se concatena texto SQL en ningún punto del proyecto. |
| A03 — Entradas malformadas | Pydantic valida longitud, rango numérico y tipo antes de que el dato llegue a la lógica de negocio. `extra="forbid"` rechaza campos no declarados. |
| A01 — Manipulación de campos | El endpoint `PATCH` solo acepta el campo `estado`; es imposible alterar el costo a través de esa ruta. |
| A04 — Estados inválidos | La política de transición impide saltos ilegales, y la base de datos tiene `CHECK` constraints como segunda línea de defensa. |
| A05 — Exposición de detalles internos | El manejador global registra la traza en el log del servidor y devuelve al cliente un mensaje genérico. |
| A02/A05 — Secretos expuestos | Las credenciales se leen de variables de entorno; `.env` está en `.gitignore` y solo se versiona `.env.example` sin datos reales. |

Validación defensiva en dos niveles: la aplicación valida, y la base de datos también.

```sql
-- sql/schema.sql
CONSTRAINT ck_prioridad_rango   CHECK (prioridad BETWEEN 1 AND 5),
CONSTRAINT ck_costo_no_negativo CHECK (costo_estimado >= 0),
CONSTRAINT ck_estado_valido     CHECK (estado IN ('registrada', 'en_proceso', 'finalizada'))
```

---

## 10. Evidencia de pruebas

Verificación manual de los endpoints contra la base de datos PostgreSQL alojada en Neon. Las salidas mostradas corresponden a una ejecución real.

### Resumen de resultados

| # | Operación | Método y ruta | Código esperado | Obtenido |
|---|---|---|---|---|
| 1 | Verificar servicio | `GET /salud` | 200 | 200 |
| 2 | Registrar solicitud | `POST /api/v1/solicitudes` | 201 | 201 |
| 3 | Listar solicitudes | `GET /api/v1/solicitudes` | 200 | 200 |
| 4 | Obtener por id | `GET /api/v1/solicitudes/{id}` | 200 | 200 |
| 5 | Actualizar solo el estado | `PATCH /api/v1/solicitudes/{id}/estado` | 200 | 200 |
| 6 | Reemplazar por completo | `PUT /api/v1/solicitudes/{id}` | 200 | 200 |
| 7 | Prioridad fuera de rango | `POST /api/v1/solicitudes` | 422 | 422 |
| 8 | Transición de estado prohibida | `PATCH /api/v1/solicitudes/{id}/estado` | 409 | 409 |
| 9 | Campo no declarado en el esquema | `POST /api/v1/solicitudes` | 422 | 422 |
| 10 | Identificador inexistente | `GET /api/v1/solicitudes/{id}` | 404 | 404 |
| 11 | Eliminar solicitud | `DELETE /api/v1/solicitudes/{id}` | 204 | 204 |
| 12 | Consultar la solicitud eliminada | `GET /api/v1/solicitudes/{id}` | 404 | 404 |

Los comandos se ejecutaron con `curl.exe` desde PowerShell. El identificador se almacenó en la variable `$ID` para no repetirlo manualmente en cada llamada.

---

### 1. Verificación del servicio

```powershell
curl.exe "http://127.0.0.1:8000/salud"
```

```json
{"estado":"ok","version":"1.0.0"}
```

### 2. Registrar una solicitud

```powershell
curl.exe -X POST "http://127.0.0.1:8000/api/v1/solicitudes" -H "Content-Type: application/json" -d '{"titulo":"Adquisición de nuevo servidor","area_solicitante":"Infraestructura TI","prioridad":3,"costo_estimado":2500.00,"estado":"registrada"}'
```

```json
{"id":"79ef0de2-ea9c-49cd-8f61-0932e8bae939","titulo":"Adquisición de nuevo servidor","area_solicitante":"Infraestructura TI","prioridad":3,"costo_estimado":"2500.00","estado":"registrada"}
```

El servidor genera el `id` como UUID; el cliente no lo envía. El costo se devuelve como texto con dos decimales exactos, según la decisión de precisión monetaria documentada en la sección 6.

### 3. Listar todas las solicitudes

```powershell
curl.exe "http://127.0.0.1:8000/api/v1/solicitudes"
```

```json
[{"id":"75a95b96-cd82-4675-a6e2-280f8ee9bec0","titulo":"Adquisición de nuevo servidor","area_solicitante":"Infraestructura TI","prioridad":3,"costo_estimado":"2500.00","estado":"registrada"},{"id":"79ef0de2-ea9c-49cd-8f61-0932e8bae939","titulo":"Adquisición de nuevo servidor","area_solicitante":"Infraestructura TI","prioridad":3,"costo_estimado":"2500.00","estado":"registrada"}]
```

### 4. Obtener una solicitud por su identificador

```powershell
curl.exe "http://127.0.0.1:8000/api/v1/solicitudes/$ID"
```

```json
{"id":"79ef0de2-ea9c-49cd-8f61-0932e8bae939","titulo":"Adquisición de nuevo servidor","area_solicitante":"Infraestructura TI","prioridad":3,"costo_estimado":"2500.00","estado":"registrada"}
```

### 5. Actualizar exclusivamente el estado

```powershell
curl.exe -X PATCH "http://127.0.0.1:8000/api/v1/solicitudes/$ID/estado" -H "Content-Type: application/json" -d '{"estado":"en_proceso"}'
```

```json
{"id":"79ef0de2-ea9c-49cd-8f61-0932e8bae939","titulo":"Adquisición de nuevo servidor","area_solicitante":"Infraestructura TI","prioridad":3,"costo_estimado":"2500.00","estado":"en_proceso"}
```

**Comprobación clave del requerimiento:** el cuerpo enviado contiene únicamente el campo `estado`, y en la respuesta el título, el área, la prioridad y el costo conservan sus valores originales. Ningún otro atributo fue modificado.

### 6. Reemplazar la solicitud por completo

```powershell
curl.exe -X PUT "http://127.0.0.1:8000/api/v1/solicitudes/$ID" -H "Content-Type: application/json" -d '{"titulo":"Adquisición de servidor y licencias","area_solicitante":"Infraestructura TI","prioridad":2,"costo_estimado":4100.50,"estado":"en_proceso"}'
```

```json
{"id":"79ef0de2-ea9c-49cd-8f61-0932e8bae939","titulo":"Adquisición de servidor y licencias","area_solicitante":"Infraestructura TI","prioridad":2,"costo_estimado":"4100.50","estado":"en_proceso"}
```

A diferencia del `PATCH`, aquí se envían todos los atributos y todos se sobrescriben. Esta es la distinción semántica entre ambos métodos.

---

### Casos de error

Las siguientes pruebas usan la bandera `-i` para mostrar el código de estado en la primera línea de la respuesta.

### 7. Prioridad fuera del rango permitido

```powershell
curl.exe -i -X POST "http://127.0.0.1:8000/api/v1/solicitudes" -H "Content-Type: application/json" -d '{"titulo":"Prueba invalida","area_solicitante":"QA","prioridad":9,"costo_estimado":100.00,"estado":"registrada"}'
```

```http
HTTP/1.1 422 Unprocessable Entity
content-type: application/json
```

```json
{"detail":[{"type":"string_too_short","loc":["body","area_solicitante"],"msg":"String should have at least 3 characters","input":"QA","ctx":{"min_length":3}},{"type":"less_than_equal","loc":["body","prioridad"],"msg":"Input should be less than or equal to 5","input":9,"ctx":{"le":5}}]}
```

La petición contenía dos defectos simultáneos: una prioridad de 9 (el máximo es 5) y un área de solo dos caracteres (el mínimo es 3). La respuesta reporta **ambos a la vez** e indica para cada uno el campo afectado, el motivo y el valor recibido. Esto es preferible a fallar en el primer error encontrado: el cliente puede corregir todo en un solo intento.

### 8. Transición de estado prohibida por las reglas de negocio

```powershell
curl.exe -i -X PATCH "http://127.0.0.1:8000/api/v1/solicitudes/$ID/estado" -H "Content-Type: application/json" -d '{"estado":"registrada"}'
```

```http
HTTP/1.1 409 Conflict
content-type: application/json
```

```json
{"detalle":"No se permite pasar del estado 'en_proceso' a 'registrada'."}
```

El valor `registrada` es un estado válido del enumerado, por lo que la validación de formato lo acepta. Lo que lo rechaza es la política de transición del dominio (`TransicionSecuencial`), que impide retroceder en el flujo. Por eso el código correcto es `409 Conflict` y no `422`: el dato está bien formado, pero entra en conflicto con el estado actual del recurso.

### 9. Campo no declarado en el esquema

```powershell
curl.exe -i -X POST "http://127.0.0.1:8000/api/v1/solicitudes" -H "Content-Type: application/json" -d '{"titulo":"Intento","area_solicitante":"QA","prioridad":1,"costo_estimado":50.00,"estado":"registrada","campo_extra":"x"}'
```

```http
HTTP/1.1 422 Unprocessable Entity
content-type: application/json
```

```json
{"detail":[{"type":"string_too_short","loc":["body","area_solicitante"],"msg":"String should have at least 3 characters","input":"QA","ctx":{"min_length":3}},{"type":"extra_forbidden","loc":["body","campo_extra"],"msg":"Extra inputs are not permitted","input":"x"}]}
```

El error `extra_forbidden` confirma que la configuración `extra="forbid"` está activa. Sin ella, el campo desconocido se descartaría en silencio y el cliente creería haber enviado un dato que en realidad nunca se guardó.

### 10. Identificador inexistente

```powershell
curl.exe -i "http://127.0.0.1:8000/api/v1/solicitudes/00000000-0000-0000-0000-000000000000"
```

```http
HTTP/1.1 404 Not Found
content-type: application/json
```

```json
{"detalle":"No existe una solicitud con id 00000000-0000-0000-0000-000000000000."}
```

El mensaje proviene de la excepción de dominio `SolicitudNoEncontradaError`, traducida a HTTP por el manejador centralizado. El endpoint no contiene ningún bloque `try/except`.

### 11. Eliminar una solicitud

```powershell
curl.exe -i -X DELETE "http://127.0.0.1:8000/api/v1/solicitudes/$ID"
```

```http
HTTP/1.1 204 No Content
```

Se responde `204` sin cuerpo, que es la convención REST para una eliminación exitosa: no queda ningún recurso que representar.

### 12. Consultar la solicitud ya eliminada

```powershell
curl.exe -i "http://127.0.0.1:8000/api/v1/solicitudes/$ID"
```

```http
HTTP/1.1 404 Not Found
content-type: application/json
```

```json
{"detalle":"No existe una solicitud con id 79ef0de2-ea9c-49cd-8f61-0932e8bae939."}
```

La eliminación se confirma contra la base de datos. Cabe notar que un segundo `DELETE` sobre el mismo identificador también responde `404`: la operación distingue entre haber borrado un recurso existente y intentar borrar uno que ya no está, lo que da al cliente información precisa sobre lo que ocurrió.

---

### Pruebas automatizadas

Además de la verificación manual, el proyecto incluye una suite ejecutable que valida la lógica de negocio sin depender de la base de datos:

```bash
pytest -q
```

```text
5 passed
```

Y la revisión estática de estilo y errores comunes:

```bash
ruff check .
```

```text
All checks passed!
```


## 11. Documentación de prompts de IA

Se utilizó Claude (Anthropic) como herramienta de apoyo. La estrategia fue **no pedir el proyecto completo en un solo prompt**, sino avanzar por incrementos verificables, revisando el resultado de cada paso antes de continuar. Un prompt que pide "hazme una API CRUD completa" produce código que funciona pero que es imposible de auditar y que suele mezclar responsabilidades en un solo archivo.

Cada prompt siguió la misma estructura: **rol → contexto → restricciones técnicas → alcance acotado → formato de salida esperado**.

---

### Prompt 1 — Diseño de la arquitectura (sin escribir código)

**Objetivo:** obtener una estructura de carpetas defendible antes de escribir la primera línea.

```text
Actúa como arquitecto de software backend con experiencia en Python y
diseño por capas.

Contexto: debo construir una API REST que gestiona "solicitudes
operativas" con los campos id, titulo, area_solicitante, prioridad (1-5),
costo_estimado y estado (registrada | en_proceso | finalizada). Debe
exponer 5 operaciones: listar, crear, reemplazar, eliminar y actualizar
únicamente el estado. La persistencia es PostgreSQL y el proyecto será
evaluado sobre la aplicación explícita de los principios SOLID.

Restricciones:
- Stack: Python 3.11, FastAPI, SQLAlchemy 2.0, Pydantic v2, psycopg 3.
- El proyecto seguirá creciendo en prácticas posteriores, así que debe
  ser escalable.

Tarea (solo esta, no avances más):
1. Propón la estructura de carpetas y archivos, indicando en una tabla la
   responsabilidad única de cada módulo.
2. Indica en qué archivo concreto quedará evidenciado cada uno de los
   cinco principios SOLID.
3. Señala qué decisiones podrían considerarse sobre-ingeniería para este
   tamaño de proyecto y por qué las recomiendas o no.

NO escribas código todavía. Quiero validar la arquitectura primero.
```

**Respuesta obtenida:** propuso la separación en `domain / infrastructure / services / api`, con el detalle de que el dominio no debe importar librerías externas. Ubicó SRP en la separación de capas, OCP en una política de transición de estados, LSP en un repositorio alternativo en memoria, ISP en la división del repositorio en lector y escritor, y DIP en la inyección de dependencias de FastAPI. Advirtió que separar la entidad de dominio del modelo ORM añade código de traducción que podría verse como sobre-ingeniería en un CRUD pequeño.

**Análisis crítico y ajustes aplicados:**

- Acepté la separación entidad/modelo ORM a pesar de la advertencia, porque el enunciado indica explícitamente que la práctica seguirá creciendo y porque es justamente lo que hace demostrable el principio de inversión de dependencias.
- Rechacé una sugerencia inicial de agregar una capa de *Unit of Work*: para cinco endpoints sin operaciones transaccionales compuestas, habría añadido complejidad sin beneficio real. Se descartó conscientemente.
- Añadí por decisión propia la carpeta `sql/` con el esquema explícito, que no venía en la propuesta, para no depender exclusivamente de `create_all()` y poder versionar los cambios de la base de datos.

---

### Prompt 2 — Capa de dominio, con exigencia explícita de seguridad

**Objetivo:** generar solo el núcleo, con los criterios de seguridad declarados por adelantado.

```text
Continuamos con la arquitectura acordada. Implementa ÚNICAMENTE la capa
de dominio: app/domain/entities.py y app/domain/repositories.py.

Requisitos de código limpio:
- Nombres descriptivos en español, sin abreviaturas.
- Docstrings que expliquen el porqué de las decisiones, no el qué.
- Tipado completo en todas las firmas.
- Ninguna función debe superar las 20 líneas.

Requisitos de seguridad:
- Los estados válidos deben ser un enumerado cerrado, no cadenas libres,
  para que sea imposible persistir un estado arbitrario.
- costo_estimado debe usar Decimal y NO float, por precisión monetaria.
- La entidad debe ser inmutable para evitar mutaciones compartidas entre
  capas.

Requisito de diseño:
- Aplica ISP separando el repositorio en interfaces de lectura y escritura.
- El módulo de dominio NO debe importar FastAPI, SQLAlchemy ni Pydantic.

No implementes todavía el repositorio de PostgreSQL ni los endpoints.
```

**Respuesta obtenida:** entregó la entidad como `dataclass(frozen=True, slots=True)`, el enumerado de estados y las tres clases abstractas del repositorio. Los métodos de lectura devolvían `SolicitudOperativa | None`.

**Análisis crítico y ajustes aplicados:**

- **Corrección de una inconsistencia de contrato:** la versión generada tenía `eliminar` devolviendo `None` mientras `obtener_por_id` devolvía `None` para indicar ausencia. Eso hacía imposible distinguir "se eliminó" de "no existía". Cambié la firma a `-> bool`. Sin este ajuste el endpoint `DELETE` habría respondido `204` incluso para identificadores inexistentes, que es un error de contrato REST.
- **Corrección de LSP:** el borrador dejaba que cada implementación decidiera si lanzar excepción o devolver `None` ante un registro faltante. Eso rompe la sustituibilidad. Documenté en las interfaces que **toda** implementación devuelve `None` y que la traducción a excepción ocurre en el servicio.
- Añadí el método `con_estado` a la entidad, que no venía en la respuesta, para que la inmutabilidad fuera utilizable en la práctica.
- La IA usó `class EstadoSolicitud(str, Enum)`. El linter marcó `UP042` porque en Python 3.11+ lo correcto es `StrEnum`; se corrigió manualmente.

---

### Prompt 3 — Repositorio de PostgreSQL con revisión de inyección SQL

**Objetivo:** implementar la persistencia y auditar el resultado antes de aceptarlo.

```text
Implementa ahora app/infrastructure/postgres_repository.py, que cumple la
interfaz RepositorioSolicitudes ya definida.

Restricciones de seguridad (obligatorias):
- Prohibido construir SQL mediante concatenación o f-strings. Usa
  exclusivamente el lenguaje de expresiones de SQLAlchemy 2.0 para que
  los valores viajen como parámetros ligados.
- No captures excepciones para silenciarlas.
- El método cambiar_estado debe modificar el campo estado y ningún otro.

Restricciones de diseño:
- El repositorio recibe la Session por constructor; no la crea ni la
  cierra (eso corresponde a la capa de dependencias).
- Incluye una función privada que traduzca del modelo ORM a la entidad de
  dominio, para no duplicar el mapeo en cada método.

Después de escribir el código, revísalo tú mismo y respóndeme:
¿en qué línea exacta podría existir riesgo de inyección SQL, y por qué no
lo hay? Si detectas alguna, corrígela.
```

**Respuesta obtenida:** el repositorio con `select()` y `session.get()`, más la función `_a_entidad`. En la autorrevisión confirmó que ningún valor se interpola en texto SQL y explicó que `session.get()` genera una consulta parametrizada por clave primaria.

**Análisis crítico y ajustes aplicados:**

- **Verificación independiente:** no acepté la autoevaluación sin comprobarla. Ejecuté la aplicación con `DEBUG=true` para que SQLAlchemy imprimiera el SQL generado y confirmé en el log que los valores aparecen como parámetros (`%(id_1)s`) y no incrustados en la sentencia.
- **Vulnerabilidad de diseño detectada por mí:** el borrador de `cambiar_estado` recibía el estado como `str` y lo asignaba directamente a la columna. Un valor arbitrario habría llegado hasta la base de datos y solo habría fallado ahí, con un error 500 poco informativo. Cambié el parámetro al tipo `EstadoSolicitud`, de modo que el valor inválido se rechaza en el borde de la API con un `422` claro.
- **Corrección de mapeo:** el código devolvía el modelo ORM directamente. Eso filtra un objeto acoplado a SQLAlchemy hacia las capas superiores y rompe la inversión de dependencias. Forcé que todos los métodos devuelvan la entidad de dominio.
- Agregué `pool_pre_ping=True` en el engine, que la IA no incluyó, porque las bases gestionadas como Neon cierran conexiones inactivas y sin esa opción la primera petición tras un periodo de inactividad falla.

---

### Prompt 4 — Auditoría final de seguridad y código limpio

**Objetivo:** usar la IA como revisor, no como generador.

```text
Actúa ahora como revisor de seguridad de código con el OWASP Top 10 como
marco de referencia. Te comparto el proyecto completo (endpoints,
esquemas, servicio, repositorio y manejadores de error).

No reescribas el proyecto. Entrégame:
1. Una tabla con cada hallazgo: severidad, archivo, línea y la categoría
   OWASP correspondiente.
2. Para cada hallazgo, el cambio mínimo que lo corrige.
3. Una lista de puntos donde el código viola algún principio de código
   limpio (duplicación, nombres poco claros, funciones largas).
4. Un apartado de "falsos positivos": cosas que parecen problemas pero no
   lo son en este contexto, con su justificación.
```

**Respuesta obtenida:** cuatro hallazgos, ordenados por severidad:

| Severidad | Hallazgo |
|---|---|
| Alta | El manejador genérico de excepciones devolvía `str(exc)` al cliente, exponiendo detalles internos (A05). |
| Media | Ausencia de límite de longitud en los campos de texto, lo que permitía cargas de gran tamaño (A04). |
| Media | Los esquemas aceptaban campos no declarados y los descartaban en silencio. |
| Baja | Sugerencia de agregar autenticación por token. |

**Análisis crítico y ajustes aplicados:**

- **Aceptado (alta):** reemplacé el mensaje detallado por uno genérico y moví la traza al log del servidor con `logger.exception`. Este era un fallo real que yo había pasado por alto.
- **Aceptado (media):** agregué `max_length` a `titulo` y `area_solicitante`, alineado con el `VARCHAR` de la tabla.
- **Aceptado (media):** añadí `extra="forbid"` en la configuración de los esquemas. Ahora un campo desconocido produce `422` en lugar de ignorarse, lo que evita que un cliente crea que envió un dato que en realidad se perdió.
- **Rechazado con justificación (baja):** no implementé autenticación. El enunciado de la práctica define cinco endpoints CRUD y no incluye gestión de usuarios; añadir un esquema de tokens habría ampliado el alcance sin ser requerido. Queda documentado como el siguiente paso natural cuando la práctica crezca.
- **Falso positivo señalado correctamente por la IA:** marcó como riesgo la ausencia de rate limiting, pero aclaró que corresponde a la capa de infraestructura (proxy inverso o gateway) y no al código de la aplicación. Coincido y no se realizó ningún cambio.

---

### Hallazgo adicional durante las pruebas

Los datos de prueba sugeridos por la IA para el caso de prioridad inválida
usaban `"area_solicitante": "QA"`. Al ejecutar la petición, la respuesta 422
reportó **dos** errores en lugar de uno: la prioridad fuera de rango, que era
el caso que se quería probar, y adicionalmente `string_too_short` en el área,
porque `"QA"` tiene dos caracteres y el mínimo definido en el esquema son tres.

El caso de prueba no estaba aislando la condición que decía verificar. Se
corrigió reemplazando el valor por `"Calidad"` en el archivo `docs/api.http`.

El detalle es menor, pero ilustra el patrón general de esta práctica: la IA
produce artefactos que parecen correctos porque el resultado observado
coincide con el esperado (en este caso, un 422), y solo al leer el detalle de
la respuesta se descubre que coincidía por un motivo distinto al buscado.

---

### Conclusión sobre el uso de IA

La herramienta resultó eficaz para acelerar la escritura de código repetitivo y para actuar como revisor de seguridad, pero produjo al menos cuatro defectos reales que solo se detectaron al revisar el resultado: una firma inconsistente en `eliminar`, un contrato ambiguo que rompía la sustituibilidad, la exposición de detalles internos en los errores y la filtración del modelo ORM hacia las capas superiores.

La lección práctica es que la calidad del resultado dependió menos de la herramienta que de dos decisiones del prompt: **acotar el alcance de cada petición** y **declarar los criterios de seguridad y diseño por adelantado** en lugar de esperar que el modelo los infiriera.

---

## Autor

**Nombre:** Jennifer Yulissa Lourdes Taperio Manuel

**Carné:** 202103763

**Sección:** B

**Curso:** Software Avanzado
