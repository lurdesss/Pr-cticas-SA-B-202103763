# Arquitectura de Aroma

Los tres diagramas que exige la practica: comunicacion entre servicios,
despliegue y modelo entidad-relacion. Estan en Mermaid, asi que GitHub los
renderiza directamente en el navegador; el codigo fuente sirve ademas como
documentacion versionable.

---

## 1. Diagrama de arquitectura (comunicacion entre servicios)

```mermaid
flowchart TB
    Navegador["Navegador<br/>cookie HttpOnly"]

    subgraph Publico["Superficie publica · puerto 8080"]
        Edge["edge (nginx)<br/>sirve el frontend<br/>y reenvia /api"]
    end

    subgraph Interna["Red interna aroma · sin puertos publicos"]
        GW["API Gateway<br/>Node.js · Express"]
        AUTH["auth-service<br/>Python · FastAPI<br/>(Practica 2)"]
        AUTHZ["authz-service<br/>Python · FastAPI<br/>(Practica 2)"]
        CAT["catalogo-service<br/>Node.js · GraphQL"]
        INV["inventario-service<br/>Python · GraphQL"]
        PED["pedidos-service<br/>Node.js · REST"]
        RES["resenas-service<br/>Python · REST"]
        DB[("PostgreSQL<br/>5 bases separadas")]
    end

    Navegador -->|HTTP| Edge
    Edge -->|/api/**| GW

    GW -->|"1. GET /auth/yo<br/>quien es"| AUTH
    GW -->|"2. POST /autorizacion/verificar<br/>que puede hacer<br/>reintentos + backoff"| AUTHZ
    GW -->|"3. proxy + cabeceras de identidad"| CAT
    GW --> INV
    GW --> PED
    GW --> RES

    PED -.->|"consulta directa<br/>precio vigente (GraphQL)"| CAT

    AUTH --> DB
    CAT --> DB
    INV --> DB
    PED --> DB
    RES --> DB
```

### Como se lee

1. El navegador nunca habla con un microservicio: solo con el **edge**.
2. El **gateway** resuelve dos preguntas distintas antes de reenviar nada.
   *Quien eres* se la hace al servicio de autenticacion, que es el unico que
   conoce el secreto del JWT. *Que puedes hacer* se la hace al microservicio
   de autorizacion, que es el unico que conoce la matriz de permisos.
3. Si ambas responden que si, el gateway reenvia la peticion agregando
   `X-Usuario-Id`, `X-Usuario-Rol` y `X-Usuario-Nombre`. Los servicios de
   negocio no abren tokens: reciben una identidad ya verificada.
4. La flecha punteada es la unica comunicacion directa entre microservicios:
   pedidos le pregunta al catalogo el precio vigente en lugar de guardar una
   copia que se desincronizaria.

---

## 2. Diagrama de despliegue

```mermaid
flowchart TB
    subgraph Host["Maquina anfitriona · Docker Engine"]
        subgraph Red["red bridge: aroma-p4_aroma"]
            E["contenedor aroma-edge<br/>nginx:1.27-alpine<br/>80 -> host 8080"]
            G["contenedor aroma-gateway<br/>node:20-alpine<br/>8000 -> host 8000"]
            A["contenedor aroma-auth<br/>python:3.11-slim<br/>8000 -> host 8081"]
            Z["contenedor aroma-authz<br/>python:3.11-slim<br/>8001 -> host 8082"]
            C["contenedor aroma-catalogo<br/>node:20-alpine<br/>4001 -> host 4001"]
            I["contenedor aroma-inventario<br/>python:3.11-slim<br/>4002 -> host 4002"]
            P["contenedor aroma-pedidos<br/>node:20-alpine<br/>4003 -> host 4003"]
            R["contenedor aroma-resenas<br/>python:3.11-slim<br/>4004 -> host 4004"]
            D["contenedor aroma-postgres<br/>postgres:16-alpine<br/>5432 -> host 5433"]
        end
        V[("volumen datos-postgres<br/>persistencia entre reinicios")]
    end

    Usuario(["Navegador"]) -->|http://localhost:8080| E
    E --> G
    G --> A & Z & C & I & P & R
    A & C & I & P & R --> D
    D --- V
```

Los puertos publicados hacia el host, salvo el 8080, existen solo para
depurar y calificar (abrir `/docs` de FastAPI, el sandbox de GraphQL). En un
despliegue real se cierran todos menos el del edge.

### Salida al exterior: hoy y manana

En Docker Compose el punto de entrada es el contenedor `edge`, que publica
el puerto 8080. Ese contenedor cumple el papel que en Kubernetes cumpliria
un `Service` de tipo `LoadBalancer` o un `Ingress`. En
[exposicion-externa.md](exposicion-externa.md) esta la equivalencia y los
manifiestos de ejemplo en la carpeta `k8s/`.

---

## 3. Diagrama entidad-relacion

Cada microservicio tiene su **propia base de datos**. No hay llaves foraneas
que crucen la frontera de un servicio: la relacion entre un pedido y un
producto se guarda como un identificador suelto, y la resuelve una llamada a
la API, no un `JOIN`.

### auth_db · servicio de autenticacion (Practica 2)

```mermaid
erDiagram
    USUARIOS {
        int      id PK
        text     nombre_cifrado "AES-256-GCM"
        text     correo_cifrado "AES-256-GCM"
        char64   correo_indice  "HMAC-SHA256, indice ciego"
        text     password_hash  "bcrypt"
        text     rol            "admin | cliente"
        datetime creado_en
    }
```

### catalogo_db · catalogo

```mermaid
erDiagram
    CATEGORIAS ||--o{ PRODUCTOS : agrupa

    CATEGORIAS {
        serial id PK
        text   nombre UK
        text   descripcion
    }

    PRODUCTOS {
        serial   id PK
        int      categoria_id FK
        text     nombre
        text     descripcion
        numeric  precio
        boolean  disponible
        datetime creado_en
    }
```

### inventario_db · inventario

```mermaid
erDiagram
    INSUMOS ||--o{ MOVIMIENTOS : registra

    INSUMOS {
        serial   id PK
        varchar  nombre UK
        varchar  unidad
        numeric  existencia
        numeric  minimo
        datetime actualizado_en
    }

    MOVIMIENTOS {
        serial   id PK
        int      insumo_id FK
        varchar  tipo "entrada | salida | ajuste"
        numeric  cantidad
        varchar  motivo
        varchar  usuario_id "id externo, sin FK"
        datetime creado_en
    }
```

### pedidos_db · pedidos

```mermaid
erDiagram
    PEDIDOS ||--|{ PEDIDO_ITEMS : contiene

    PEDIDOS {
        serial   id PK
        text     usuario_id "id externo, sin FK"
        text     usuario_nombre
        text     estado "recibido | preparando | listo | entregado | cancelado"
        text     notas
        numeric  total
        datetime creado_en
    }

    PEDIDO_ITEMS {
        serial  id PK
        int     pedido_id FK
        text    producto_id "id externo del catalogo, sin FK"
        text    nombre_producto "copia historica"
        numeric precio_unitario "copia historica"
        int     cantidad
    }
```

`nombre_producto` y `precio_unitario` se copian a proposito. Si manana sube
el precio del latte, los pedidos de ayer deben seguir mostrando lo que se
cobro entonces. Es la diferencia entre un dato de referencia y un dato
historico.

### resenas_db · resenas

```mermaid
erDiagram
    RESENAS {
        serial   id PK
        varchar  producto_id "id externo, sin FK"
        varchar  usuario_id  "id externo, sin FK"
        varchar  usuario_nombre
        int      calificacion "1..5"
        text     comentario
        datetime creado_en
    }
```

Restriccion `UNIQUE (producto_id, usuario_id)`: una persona opina una vez
por producto. Sin ella, cualquiera podria inflar el promedio repitiendo la
misma resena.
