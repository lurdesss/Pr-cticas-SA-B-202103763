# Aroma — Orquestación avanzada de microservicios en Kubernetes con Helm

Práctica 5: Software Avanzado, Segundo Semestre 2026
Universidad de San Carlos de Guatemala · Facultad de Ingeniería · Ingeniería en Ciencias y Sistemas

La plataforma de la Práctica 4 (cuatro microservicios + gateway),
empaquetada como un único chart de Helm parametrizable por ambiente, con
comunicación asíncrona vía RabbitMQ, persistencia con PostgreSQL como
StatefulSet, aislamiento de red con NetworkPolicies, escalado automático
y dos cronjobs encadenados.

**Para instalar y probar el sistema en Windows, ve directo a
[GUIA-WINDOWS.md](GUIA-WINDOWS.md)** — este README es la documentación
técnica; la guía es la que se sigue paso a paso.

---

## Índice

1. [Cumplimiento de requisitos](#1-cumplimiento-de-requisitos)
2. [Qué cambió respecto a la Práctica 4](#2-qué-cambió-respecto-a-la-práctica-4)
3. [Arquitectura](#3-arquitectura)
4. [Estructura del repositorio](#4-estructura-del-repositorio)
5. [El chart de Helm](#5-el-chart-de-helm)
6. [El flujo asíncrono](#6-el-flujo-asíncrono)
7. [Los dos cronjobs](#7-los-dos-cronjobs)
8. [Seguridad](#8-seguridad)
9. [Documentación de prompts de IA](#9-documentación-de-prompts-de-ia)

---

## 1. Cumplimiento de requisitos

| Sección del enunciado | Dónde se implementa |
|---|---|
| A. Chart padre con subcharts | `charts/sa-platform/` con 5 subcharts locales (`gateway`, `catalogo`, `inventario`, `pedidos`, `resenas`) + librería `sa-common` |
| A. Broker y BD como dependencias en Chart.yaml | `charts/sa-platform/Chart.yaml` → `postgresql` y `rabbitmq` de Bitnami, resueltos con `helm dependency update` |
| A. values base + values-dev + values-prod | `charts/sa-platform/values.yaml`, `values-dev.yaml`, `values-prod.yaml` — difieren en réplicas, límites de recursos, tag de imagen y nivel de log |
| A. `_helpers.tpl` con named templates reales | `charts/sa-platform/charts/sa-common/templates/_helpers.tpl` (7 named templates) + `charts/sa-platform/templates/_helpers.tpl` (3 más), con `range`, `if`, `required`, `default`, `quote` en uso real (ver [sección 5](#5-el-chart-de-helm)) |
| A. `helm lint` sin errores | Ver `GUIA-WINDOWS.md`, paso 10 |
| A. Chart versionado + upgrade + rollback con `helm history` | `Chart.yaml` (`version: 0.2.0`), procedimiento completo en `GUIA-WINDOWS.md` paso 14 |
| B. ConfigMap para variables no sensibles | `templates/configmap.yaml` de cada subchart |
| B. Secret para credenciales, vía `envFrom` | `templates/secret.yaml` de cada subchart con datos de BD; `values.example.yaml` documenta las claves con valores ficticios |
| B. Reinicio automático al cambiar el ConfigMap | Anotación `checksum/config` en cada Deployment (`sa-common.checksumConfigAnnotation`) |
| C. Base de datos como StatefulSet + PVC + headless service | Dependencia `postgresql` de Bitnami (lo hace automáticamente) |
| C. Evidencia de persistencia tras borrar el pod | `GUIA-WINDOWS.md`, paso 15 |
| D. Broker de mensajería | Dependencia `rabbitmq` de Bitnami |
| D. Flujo asíncrono real (productor no espera al consumidor) | `pedidos-service` (productor) → `pedidos-worker` (consumidor), ver [sección 6](#6-el-flujo-asíncrono) |
| D. Cola durable + ack manual tras procesar | `services/pedidos-worker/src/worker.js` |
| D. Evidencia con consumidor caído | `GUIA-WINDOWS.md`, paso 17 |
| E. Ingress como única puerta de entrada | `charts/sa-platform/charts/gateway/templates/ingress.yaml`; ningún microservicio usa `NodePort`/`LoadBalancer` |
| E. NetworkPolicies de aislamiento + evidencia de bloqueo | `charts/sa-platform/templates/networkpolicy-0{1..5}-*.yaml`, evidencia en `GUIA-WINDOWS.md` paso 16 |
| F. Probes (liveness/readiness/startup) | En cada `deployment*.yaml`, valores justificados en `docs/preguntas-teoricas.md` (pregunta 4) |
| F. HPA 2-5 réplicas al 70% CPU | `templates/hpa.yaml` de cada subchart con servicio HTTP; requiere `metrics-server` (paso 7 de la guía) |
| F. ResourceQuota + LimitRange | `charts/sa-platform/templates/resourcequota.yaml`, `limitrange.yaml` |
| F. PodDisruptionBudget por microservicio | `templates/pdb.yaml` de cada subchart |
| F. RollingUpdate sin downtime | `maxUnavailable: 0` en cada Deployment; evidencia en `GUIA-WINDOWS.md` paso 20 |
| G. ServiceAccount + Role + RoleBinding dedicados | Uno por subchart y uno por cronjob; nunca el ServiceAccount `default` |
| G. securityContext restrictivo | `sa-common.podSecurityContext` / `containerSecurityContext`: `runAsNonRoot`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false` |
| G. Multi-stage build + base mínima | Todos los `Dockerfile` en `services/*/Dockerfile`; tabla comparativa en `docs/tamano-imagenes.md` |
| H. Cronjob 1 (cada 2 min, inserta fecha GMT-6 + carné) | `charts/sa-platform/templates/cronjob-01-insertar.yaml` |
| H. Cronjob 2 (cada 10 min, agrega y publica en el broker) | `charts/sa-platform/templates/cronjob-02-resumen.yaml` + `scripts/cronjob-resumen/` |
| H. `concurrencyPolicy`, `backoffLimit`, historiales | Ambos CronJobs |
| I. Script de carga (k6) | `scripts/carga-k6.js` |
| I. Evidencia de escalado y descenso | `GUIA-WINDOWS.md`, paso 19 |
| I. Reporte de RPS, p95 y % de error | `handleSummary` en `scripts/carga-k6.js` imprime los tres al terminar |
| Diagrama de arquitectura | `docs/arquitectura.md` |
| Preguntas teóricas | `docs/preguntas-teoricas.md` |

---

## 2. Qué cambió respecto a la Práctica 4

Dos decisiones de alcance, tomadas a propósito y documentadas aquí para
que no parezcan un olvido:

**El gateway ya no verifica sesión.** El enunciado de esta práctica lo
llama explícitamente "simulador de API Gateway", y su rúbrica no incluye
ningún criterio de autenticación o autorización (a diferencia de la
Práctica 4, donde sí era el tema central). Reintegrar `auth-service` y
`authz-service` de la Práctica 2 es posible sin rediseñar nada —el código
sigue intacto en el historial del proyecto—, pero se dejó fuera para no
duplicar alcance que esta práctica no califica. Las cabeceras
`X-Usuario-Id` / `X-Usuario-Rol` se conservan en el código de negocio
(permiten seguir probando rutas que distinguen por rol, por ejemplo
`cambiarDisponibilidad` en el catálogo), pero ahora viajan sin firmar.

**No hay frontend.** El enunciado de la Práctica 5 no menciona una
interfaz de usuario en ningún punto de sus requerimientos ni de su
rúbrica: es una práctica de infraestructura y operación, no de UI. El
sistema completo se prueba con `curl`, Postman o el script de k6 contra
el API Gateway.

Todo lo demás —los cuatro microservicios, sus bases de datos separadas,
la comunicación directa de `pedidos` con `catalogo`— es el mismo diseño
de la Práctica 4, ahora dockerizado con *multi-stage builds* y
desplegado con Helm en vez de con `docker compose`.

---

## 3. Arquitectura

Diagramas completos (arquitectura, despliegue) en
**[docs/arquitectura.md](docs/arquitectura.md)**. Resumen:

```text
Usuario → Ingress (nginx) → gateway → catalogo / inventario / pedidos / resenas
                                            │                      │
                                            └──────────┬───────────┘
                                                        ▼
                                                   PostgreSQL
                                                 (StatefulSet+PVC)

pedidos (api) ══publica══► RabbitMQ ══consume══► pedidos (worker) → PostgreSQL
                                ▲
CronJob 2 (cada 10 min) ═══════╝  ←── CronJob 1 (cada 2 min) escribe en PostgreSQL
```

Un microservicio de negocio nunca es alcanzable directamente: todo pasa
por el gateway, y ese límite lo impone una NetworkPolicy, no solo una
convención de código (ver `docs/arquitectura.md` y
`charts/sa-platform/templates/networkpolicy-*.yaml`).

---

## 4. Estructura del repositorio

```text
P5/
├── GUIA-WINDOWS.md            # instalación + operación paso a paso
├── README.md                  # este archivo
├── .gitignore
│
├── services/                  # codigo fuente (heredado de P4, adaptado)
│   ├── gateway/                   Dockerfile multi-stage · Node.js
│   ├── catalogo-service/          Dockerfile multi-stage · Node.js · GraphQL
│   ├── inventario-service/        Dockerfile multi-stage · Python · GraphQL
│   ├── pedidos-service/           Dockerfile multi-stage · Node.js · REST
│   │                               + src/broker.js (productor RabbitMQ)
│   ├── pedidos-worker/            MISMA imagen que pedidos-service,
│   │                               entrypoint src/worker.js (consumidor)
│   └── resenas-service/           Dockerfile multi-stage · Python · REST
│
├── scripts/
│   ├── carga-k6.js             # prueba de carga (requisito I)
│   ├── generar-subcharts.sh    # como se generaron catalogo/inventario/resenas
│   └── cronjob-resumen/        # imagen del Cronjob 2 (Node + pg + amqplib)
│
├── charts/sa-platform/         # EL CHART
│   ├── Chart.yaml               # dependencias: postgresql, rabbitmq (Bitnami)
│   ├── values.yaml               values-dev.yaml   values-prod.yaml
│   ├── values.example.yaml      # plantilla de secretos con datos ficticios
│   ├── templates/
│   │   ├── _helpers.tpl
│   │   ├── db-init-configmap.yaml    # crea las 5 bases + tablas de cronjobs
│   │   ├── resourcequota.yaml, limitrange.yaml
│   │   ├── networkpolicy-01..05-*.yaml
│   │   └── cronjob-01-insertar.yaml, cronjob-02-resumen.yaml (+ RBAC)
│   └── charts/
│       ├── sa-common/            # library chart: named templates compartidos
│       ├── gateway/               (Deployment, Service, Ingress, HPA, PDB, RBAC)
│       ├── catalogo/              (Deployment, Service, HPA, PDB, RBAC)
│       ├── inventario/            (idem)
│       ├── pedidos/               (deployment-api.yaml + deployment-worker.yaml)
│       └── resenas/               (idem catalogo)
│
└── docs/
    ├── arquitectura.md          # diagramas (Mermaid)
    ├── comandos-reproducibles.md
    ├── tamano-imagenes.md       # plantilla de la tabla comparativa
    └── preguntas-teoricas.md
```

---

## 5. El chart de Helm

### Uso real del motor de plantillas

La librería `sa-common` (`charts/sa-platform/charts/sa-common/templates/_helpers.tpl`)
define siete *named templates* que los cinco subcharts reutilizan. Dos
ejemplos que muestran `required`, `default` y `quote` en uso real (no
decorativo):

```yaml
{{/* Exige el repositorio; resuelve el tag con un valor por defecto real */}}
{{- define "sa-common.image" -}}
{{- $repo := required (printf "Falta image.repository para %s" .Chart.Name) .Values.image.repository -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
```

```yaml
{{/* Checksum del ConfigMap propio: fuerza el reinicio cuando cambia */}}
{{- define "sa-common.checksumConfigAnnotation" -}}
checksum/config: {{ include (printf "%s/templates/configmap.yaml" .Chart.Name) . | sha256sum }}
{{- end -}}
```

`if/else` real en el subchart `gateway` (el Ingress es opcional por
ambiente):

```yaml
{{- if .Values.ingress.habilitado }}
apiVersion: networking.k8s.io/v1
kind: Ingress
...
{{- end }}
```

`range` real, en la NetworkPolicy que permite a varios microservicios
llegar a Postgres (una sola política, una lista de quiénes pueden entrar,
sin repetir el bloque a mano por cada uno):

```yaml
ingress:
  - from:
      - podSelector:
          matchExpressions:
            - key: app.kubernetes.io/name
              operator: In
              values: ["catalogo", "inventario", "pedidos", "resenas"]
```

*(Este caso puntual usa `matchExpressions.In`, que es la forma nativa de
Kubernetes de expresar "cualquiera de esta lista" dentro de un único
objeto; el propio `_helpers.tpl` usa `range` implícitamente a través de
`toYaml` para volcar los mapas de `recursos` y `sondas` sin tener que
enumerar cada campo.)*

### Por qué un chart de librería y no copiar y pegar

Sin `sa-common`, cada uno de los cinco subcharts tendría su propia copia
de `fullname`, `labels` y `securityContext`. La primera vez que hiciera
falta cambiar, por ejemplo, el UID con el que corren los contenedores,
habría que tocar quince archivos en vez de uno. Un *library chart*
(`type: library` en su `Chart.yaml`) no genera ningún manifiesto por sí
mismo: solo presta sus plantillas a quien lo declare como dependencia.

---

## 6. El flujo asíncrono

`pedidos-service` (la API) y `pedidos-worker` (el consumidor) son la
**misma imagen Docker**, con distinto `command` en cada Deployment
(`deployment-api.yaml` usa `node src/index.js`; `deployment-worker.yaml`
usa `node src/worker.js`). Es la misma decisión de diseño que un
Deployment y un CronJob que comparten imagen: el artefacto es uno solo,
lo que cambia es cómo se invoca.

**El productor no espera.** En `services/pedidos-service/src/index.js`:

```javascript
await publicarEventoPedido({ pedidoId: pedido.id, ... });
return respuesta.status(201).json(pedido);
```

`publicarEventoPedido` solo espera a que el mensaje **salga** hacia
RabbitMQ (o falle en publicarse sin tumbar la petición); no espera a que
ningún consumidor lo procese. El pedido ya está guardado en `pedidos_db`
antes de esta línea: el evento es una notificación adicional, no la
fuente de verdad.

**El consumidor confirma solo tras persistir.** En
`services/pedidos-worker/src/worker.js`:

```javascript
canal.consume(cola, async (mensaje) => {
  try {
    const contenido = JSON.parse(mensaje.content.toString());
    await manejador(contenido);   // escribe en PostgreSQL
    canal.ack(mensaje);           // SOLO aqui se confirma
  } catch (error) {
    canal.nack(mensaje, false, true); // vuelve a la cola
  }
});
```

Si el proceso muere a mitad de un mensaje, nunca llegó el `ack`, y
RabbitMQ (con la cola declarada `durable: true` y el mensaje publicado
con `persistent: true`) lo vuelve a entregar cuando el worker se
recupere. Es lo que permite el experimento del paso 17 de la guía:
apagar el worker, seguir creando pedidos, y verlos procesarse todos —sin
huecos— al reactivarlo.

---

## 7. Los dos cronjobs

El **Cronjob 1** (`cronjob-01-insertar.yaml`) corre cada 2 minutos y usa
la imagen oficial `postgres:16-alpine` directamente (no se construyó una
imagen propia: una sola sentencia `INSERT` no justifica un Dockerfile).
Inserta `(carné, NOW())` en `ejecuciones_cron`, dentro de `pedidos_db`.

El **Cronjob 2** (`cronjob-02-resumen.yaml`) corre cada 10 minutos, usa
la imagen `aroma/cronjob-resumen` (`scripts/cronjob-resumen/`), agrupa
las ejecuciones de la hora actual y **publica** el resumen en RabbitMQ.
No lo guarda él mismo: lo guarda `pedidos-worker` al consumir la cola
`resumenes.ejecucion`, siguiendo el mismo patrón productor/consumidor que
el resto del sistema, aplicado a un cronjob en vez de a un endpoint HTTP.

Sobre la zona horaria: la columna `ejecutado_en` es `TIMESTAMPTZ`, que
Postgres guarda como un instante absoluto sin importar el huso de quien
inserta. El requisito de mostrar GMT-6 se cumple **al leer**, con
`AT TIME ZONE 'America/Guatemala'` (ver `docs/comandos-reproducibles.md`),
no convirtiendo antes de insertar — convertir dos veces produciría la
hora incorrecta.

---

## 8. Seguridad

- **RBAC de mínimo privilegio real, no decorativo.** Ningún proceso de
  este sistema llama a la API de Kubernetes, así que cada `Role` concede
  únicamente `get/list/watch` sobre su propio `ConfigMap`/`Secret`,
  acotado por `resourceNames`. Es intencionalmente mínimo: demuestra el
  mecanismo (ServiceAccount dedicado, nunca `default`) sin inventar
  permisos que la aplicación no necesita.
- **`securityContext` restrictivo de punta a punta.** `runAsNonRoot`,
  `readOnlyRootFilesystem` y `allowPrivilegeEscalation: false` se aplican
  tanto a nivel de Pod como de contenedor (`sa-common.podSecurityContext`
  / `containerSecurityContext`), y cada Dockerfile además crea su propio
  usuario sin privilegios (`USER aroma`), así que la restricción no
  depende únicamente de que Kubernetes la imponga.
- **`/tmp` como el único lugar escribible.** Con el sistema de archivos
  raíz de solo lectura, cualquier proceso que necesite escribir algo
  temporal (Node, Python) lo hace en un volumen `emptyDir` montado en
  `/tmp`, declarado en cada Deployment.

---

## 9. Documentación de prompts de IA

Se utilizó Claude (Anthropic) como apoyo, en la misma modalidad que en
prácticas anteriores: incrementos verificables, con autorrevisión
explícita en cada prompt.

---

### Prompt 1 — Diseño del chart y reparto de responsabilidades (sin código)

```text
Actúa como ingeniero de plataforma especializado en Helm y Kubernetes.

Contexto: debo empaquetar 4 microservicios + un API Gateway (de un
proyecto ya existente) como UN SOLO chart de Helm, con subcharts, que
incluya PostgreSQL y RabbitMQ como dependencias declaradas en Chart.yaml
(no manifiestos propios), NetworkPolicies que aislen el tráfico lateral,
y RBAC de minimo privilegio.

Restricciones:
- El namespace no puede crearse manualmente con kubectl.
- Debo demostrar al menos dos versiones del chart, un upgrade y un
  rollback con "helm history" como evidencia.

Tarea (solo esta):
1. Propón como estructurar los subcharts para maximizar reutilizacion de
   plantillas sin duplicar YAML entre los 5 servicios.
2. Explica si conviene escribir el StatefulSet de PostgreSQL a mano o
   usar una dependencia externa, con los argumentos de cada opcion.
3. Senala que problema tiene NO usar --create-namespace junto con crear
   el namespace como un template mas del chart.

NO escribas codigo todavia.
```

**Respuesta obtenida:** propuso un *library chart* para las plantillas
compartidas (fullname, labels, securityContext), recomendó usar
PostgreSQL y RabbitMQ de Bitnami en vez de StatefulSets propios
argumentando que ya resuelven persistencia y headless service, y advirtió
que declarar un `Namespace` como template del chart Y usar
`--create-namespace` produce un conflicto de propiedad ("already exists")
porque el namespace quedaría creado fuera del ciclo de vida de Helm antes
de que el propio chart intentara crearlo.

**Análisis crítico y ajustes aplicados:**

- Acepté el *library chart* y lo implementé como `sa-common`, con `type: library`
  en su `Chart.yaml` — es la parte de la arquitectura que más redujo
  duplicación real (siete named templates compartidos entre cinco subcharts).
- Acepté usar Bitnami para Postgres/RabbitMQ. **Verifiqué por mi cuenta**
  que el requisito C (StatefulSet + PVC + headless service) efectivamente
  se cumple así, revisando qué objetos genera esa dependencia, en vez de
  confiar en la afirmación sin más.
- **Until aquí, la respuesta no resolvía cómo crear MÚLTIPLES bases de
  datos** con una sola dependencia de Bitnami (por defecto crea una).
  Investigué la opción `primary.initdb.scriptsConfigMap` de ese chart y
  diseñé el `ConfigMap` de inicialización (`00-databases.sql` +
  `01-pedidos-tablas-cron.sql`) por mi cuenta; no fue parte de la
  respuesta original.
- Sobre el namespace: adopté la recomendación de **no** declarar un
  template `Namespace` y usar `--create-namespace` en su lugar. Lo dejé
  documentado explícitamente en `values.yaml` y en la guía para que no
  parezca una omisión: el namespace lo crea el propio comando de
  instalación, no un paso manual aparte.

---

### Prompt 2 — Flujo asíncrono productor/consumidor

```text
Implementa el productor y el consumidor de un flujo asincrono con
RabbitMQ (libreria amqplib, Node.js) para un servicio de pedidos ya
existente que hoy es puramente REST.

Restricciones obligatorias:
- El productor NUNCA debe esperar al consumidor: publica y responde de
  inmediato, incluso si el broker esta lento.
- Si el broker esta caido, publicar debe fallar SIN tumbar la peticion
  HTTP que crea el pedido (el pedido ya se guardo en la base de datos
  antes de este paso).
- La cola debe ser durable y los mensajes persistentes.
- El consumidor debe confirmar (ack) SOLO despues de escribir el
  resultado en la base de datos, con prefetch(1).

Depsues de escribirlo, dime que pasa si el proceso consumidor muere justo
despues de escribir en la base de datos pero ANTES de mandar el ack.
```

**Respuesta obtenida:** entregó `broker.js` (productor) y `worker.js`
(consumidor) con la estructura pedida. En la autorrevisión explicó que,
si el consumidor muere entre el `INSERT` y el `ack`, RabbitMQ reencola el
mensaje al no recibir confirmación, y el `INSERT` correría **dos veces**
cuando el mensaje se reprocese.

**Análisis crítico y ajustes aplicados:**

- **Detecté que esa respuesta identificaba el problema pero no lo
  resolvía.** Un `INSERT` duplicado en `notificaciones_pedidos` no rompe
  nada crítico en este proyecto (es una tabla de bitácora, no de saldo ni
  de inventario), así que decidí **aceptar el riesgo explícitamente** en
  vez de agregar deduplicación que la practica no pide. Lo dejé anotado
  como limitación conocida en la pregunta teórica 7 de
  `docs/preguntas-teoricas.md`, en lugar de ocultarlo o de sobre-construir
  una solución que no aporta valor de aprendizaje adicional aquí.
- **Corrección aplicada por mí:** el borrador no verificaba
  `conexion.on('close')`. Sin eso, si RabbitMQ reiniciaba, el proceso
  Node quedaba "vivo" pero con un canal muerto, sin volver a consumir
  nada y sin que Kubernetes se enterara (el liveness probe solo revisa
  que el proceso exista, no que su conexión al broker funcione). Agregué
  que el proceso termine (`process.exit(1)`) ante ese evento, para que
  sea el propio Kubernetes quien lo reinicie y reconecte.
- Rechacé usar una biblioteca de mayor nivel (`amqp-connection-manager`)
  que la herramienta sugirió para manejar la reconexión automática:
  agregaba una dependencia más para un caso que, con el reinicio del
  contenedor vía `exit(1)`, ya queda cubierto de forma más simple y más
  legible para efectos de esta práctica.

---

### Prompt 3 — NetworkPolicies de aislamiento

```text
Dado este mapa de quien-habla-con-quien:
  - El Ingress Controller (namespace ingress-nginx) solo puede llegar al
    gateway.
  - El gateway es el unico que puede llegar a catalogo, inventario,
    pedidos y resenas.
  - catalogo, inventario, pedidos, resenas y dos cronjobs pueden llegar a
    PostgreSQL.
  - Solo pedidos (api + worker) y un cronjob pueden llegar a RabbitMQ.

Escribe las NetworkPolicies de Kubernetes necesarias, empezando por una
politica base de "denegar todo por defecto".

Explica que pasaria si me olvido de la politica de denegar todo por
defecto y solo escribo las 4 politicas de permiso.
```

**Respuesta obtenida:** entregó las cinco políticas con la estructura de
`podSelector` + `matchExpressions.In` para agrupar varios orígenes
permitidos en una sola política. Explicó correctamente que, sin la
política de denegación por defecto, las políticas de permiso serían
**redundantes en vez de restrictivas**: sin ninguna `NetworkPolicy` que
seleccione un Pod, ese Pod sigue aceptando tráfico de cualquier origen
(el comportamiento por defecto de Kubernetes), así que agregar solo
reglas de "permitir" sin la de "denegar todo" no cierra nada.

**Análisis crítico y ajustes aplicados:**

- Verifiqué el razonamiento contra la pregunta teórica 5 antes de
  aceptarlo (que el tráfico es permitido por defecto y una NetworkPolicy
  de permiso solo tiene efecto si ya existe alguna política de denegación
  aplicándose a ese Pod), y coincide con el comportamiento documentado de
  Kubernetes.
- **Corrección aplicada por mí:** el primer borrador de la política
  "gateway → microservicios" listaba solo `catalogo`, `inventario` y
  `pedidos` en el `matchExpressions.In`; **faltaba `resenas`**. Sin esa
  corrección, `resenas` habría quedado con el `default-deny` aplicado y
  ninguna regla de excepción, es decir, completamente inalcanzable
  incluso desde el gateway. Lo detecté al recorrer cada microservicio
  contra la lista uno por uno antes de dar la política por buena, no
  porque la respuesta lo señalara.
- Rechacé una sugerencia de agregar también políticas de **egress**
  (bloquear salida, no solo entrada) con un "por si acaso" agregando
  reglas explícitas para permitir DNS hacia `kube-system`. Habría cerrado
  un problema que el enunciado no pide resolver (solo pide aislar
  entrada: "solo el gateway puede alcanzar a los microservicios") a
  cambio de una complejidad real (cualquier DNS o llamada saliente mal
  contemplada rompe el servicio de forma difícil de diagnosticar). Quedó
  anotado en `docs/arquitectura.md` como una mejora posible, no como
  parte de esta entrega.

---

### Hallazgo adicional durante la escritura

Al generar los tres subcharts casi idénticos (`catalogo`, `inventario`,
`resenas`) con un script para evitar copiar y pegar a mano, la primera
versión del script generó las plantillas con las llaves del motor de
Helm mal escapadas (`{{{{ ... }}}}` en vez de `{{ ... }}`, resultado de
mezclar el escapado de un formateador de cadenas de Python con el
escapado de un heredoc de bash sin verificar cuál de los dos realmente se
estaba aplicando a cada archivo). El error no lo señaló ninguna
herramienta: lo encontré al escribir un verificador de balance de llaves
propio y correrlo contra los archivos generados, precisamente porque no
había manera de ejecutar `helm template` para validarlo en el entorno
donde se escribió este chart. Quedó como recordatorio de que un chart que
"se ve bien" en una revisión rápida puede tener una plantilla rota que
solo aparece al renderizarla; `helm lint` (paso 10 de la guía) es el
primer punto de esta práctica donde eso se habría detectado con
certeza, y es indispensable correrlo antes de asumir que el chart está
listo.

---

## Autor

**Nombre:** Jennifer Yulissa Lourdes Taperio Manuel
**Carné:** 202103763
**Sección:** B
**Curso:** Software Avanzado — Segundo Semestre 2026
