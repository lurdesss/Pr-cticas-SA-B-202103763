# Arquitectura de Aroma — Práctica 5

## 1. Diagrama de arquitectura (interno/externo, síncrono/asíncrono, límites de red)

```mermaid
flowchart TB
    Usuario(["Persona<br/>curl / Postman / k6"])

    subgraph Externo["Fuera del cluster"]
        Usuario
    end

    subgraph Cluster["Cluster de Kubernetes · namespace sa-p5"]
        subgraph EntradaNS["namespace ingress-nginx"]
            IC["Ingress Controller<br/>(NGINX)"]
        end

        GW["gateway<br/>Deployment · 2-5 replicas (HPA)"]

        subgraph Sincrono["Llamadas sincronas (HTTP, esperan respuesta)"]
            CAT["catalogo<br/>GraphQL · Node.js"]
            INV["inventario<br/>GraphQL · Python"]
            PED_API["pedidos (api)<br/>REST · Node.js"]
            RES["resenas<br/>REST · Python"]
        end

        PG[("postgresql<br/>StatefulSet + PVC<br/>(Bitnami)")]

        subgraph Asincrono["Flujo asincrono (no espera respuesta)"]
            MQ{{"rabbitmq<br/>StatefulSet + PVC<br/>(Bitnami)"}}
            PED_WORKER["pedidos (worker)<br/>consumidor independiente"]
        end

        CJ1["CronJob 1<br/>cada 2 min<br/>psql INSERT"]
        CJ2["CronJob 2<br/>cada 10 min<br/>calcula + publica"]
    end

    Usuario -->|"HTTPS :80/:443"| IC
    IC -->|"NetworkPolicy 02:<br/>solo este namespace"| GW

    GW -->|"NetworkPolicy 03:<br/>solo el gateway"| CAT
    GW --> INV
    GW --> PED_API
    GW --> RES

    PED_API -.->|"consulta directa<br/>(precio vigente)"| CAT

    CAT -->|"NetworkPolicy 04"| PG
    INV --> PG
    PED_API --> PG
    RES --> PG
    CJ1 -->|"NetworkPolicy 04"| PG

    PED_API ==>|"publica evento<br/>pedidos.eventos<br/>NO espera respuesta"| MQ
    MQ ==>|"consume<br/>ack manual"| PED_WORKER
    PED_WORKER --> PG

    CJ2 -->|"NetworkPolicy 04<br/>(lee ejecuciones)"| PG
    CJ2 ==>|"NetworkPolicy 05<br/>publica resumen"| MQ
    MQ ==>|"consume resumen"| PED_WORKER

    classDef async stroke-dasharray: 5 5
    class MQ,PED_WORKER async
```

**Cómo leerlo:**

- **Flechas finas (`-->`)**: llamadas síncronas por HTTP. Quien llama espera la respuesta antes de continuar (el gateway esperando a catalogo, pedidos consultando el precio vigente al catalogo, cualquier servicio hablando con Postgres).
- **Flechas gruesas (`==>`)**: el flujo asíncrono. `pedidos (api)` publica en RabbitMQ y responde al cliente HTTP de inmediato, sin esperar a que `pedidos (worker)` procese nada. El worker consume cuando puede, incluso minutos después.
- **Los límites marcados como "NetworkPolicy N"** son exactamente los que aplican los archivos `templates/networkpolicy-0N-*.yaml` del chart. Fuera de esas flechas, todo tráfico está bloqueado por la política `default-deny-ingress` (política 01): es la razón por la que el diagrama no muestra, por ejemplo, una flecha directa entre `resenas` y `rabbitmq`, o entre cualquier Pod fuera del namespace y `postgresql`.
- **Lo que queda fuera del cluster**: únicamente quien hace la petición HTTP. Ni la base de datos, ni el broker, ni ningún microservicio tienen una IP alcanzable desde fuera; la única superficie pública es el Ingress.

## 2. Diagrama de despliegue

```mermaid
flowchart TB
    subgraph Nodo["Nodo de minikube"]
        subgraph NSIngress["namespace: ingress-nginx"]
            ICP["Pod: ingress-nginx-controller"]
        end

        subgraph NS["namespace: sa-p5"]
            direction TB
            GWP["Pods: gateway (x2-5)"]
            CATP["Pods: catalogo (x2-5)"]
            INVP["Pods: inventario (x2-5)"]
            PEDP["Pods: pedidos-api (x2-5)"]
            PEDW["Pods: pedidos-worker (x1-2)"]
            RESP["Pods: resenas (x2-5)"]
            PGP["Pod: postgresql-0<br/>(StatefulSet)"]
            MQP["Pod: rabbitmq-0<br/>(StatefulSet)"]
            CJ1P["Pod efimero:<br/>cronjob-insertar<br/>(cada 2 min)"]
            CJ2P["Pod efimero:<br/>cronjob-resumen<br/>(cada 10 min)"]
        end

        PVC1[("PVC: data-postgresql-0")]
        PVC2[("PVC: data-rabbitmq-0")]
    end

    ICP -->|Service ClusterIP| GWP
    GWP -->|Service ClusterIP| CATP & INVP & PEDP & RESP
    CATP & INVP & PEDP & RESP -->|Service ClusterIP :5432| PGP
    PEDP <-->|Service ClusterIP :5672| MQP
    PEDW <-->|consume| MQP
    CJ1P --> PGP
    CJ2P --> PGP
    CJ2P --> MQP
    PGP --- PVC1
    MQP --- PVC2
```

Todos los objetos de este diagrama, salvo el nodo físico de minikube, los crea `helm install` en una sola invocación. Ningún Pod se expone con `NodePort` ni `LoadBalancer`: el único camino de entrada es el `Ingress` del subchart `gateway`.

## 3. Notas de diseño que sostienen la arquitectura

**Por qué Postgres y RabbitMQ son dependencias de Bitnami y no manifiestos propios.** Ambos ya se despliegan como `StatefulSet` con `PersistentVolumeClaim` y `Service` headless, que es exactamente el requisito C. Escribirlos a mano hubiera duplicado trabajo ya resuelto y probado por la comunidad, y esta práctica evalúa saber *empaquetar y operar* con Helm, no reimplementar un operador de base de datos.

**Por qué el gateway de esta práctica no verifica sesión.** El enunciado lo llama "simulador de API Gateway" y la rúbrica no incluye ningún criterio de autenticación/autorización (a diferencia de la Práctica 4). Reincorporar `auth-service`/`authz-service` de la Práctica 2 es posible —el código sigue existiendo— pero se dejó fuera para no duplicar alcance que esta práctica no califica. Las cabeceras `X-Usuario-Id` / `X-Usuario-Rol` siguen existiendo en el código de negocio (para poder probar rutas que distinguen rol), pero viajan sin firmar: quien las pone es quien llama.

**Por qué el worker de pedidos es un Deployment aparte y no un hilo dentro de la API.** Son dos perfiles de carga distintos: la API escala por tráfico HTTP (de ahí su HPA), el worker escala por profundidad de cola (por eso no tiene HPA y se deja en una réplica fija, para poder demostrar con claridad el escenario "consumidor caído" bajándolo a 0 manualmente). Compartir el mismo Deployment habría acoplado dos ciclos de vida que en producción se escalan de forma independiente.
