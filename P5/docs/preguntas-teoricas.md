# Preguntas teóricas

Respuestas ancladas a decisiones concretas de `charts/sa-platform`, no a
definiciones genéricas de la documentación oficial.

---

## 1. ¿Qué es Helm y qué problema resuelve frente a los manifiestos sueltos?

Helm es el gestor de paquetes de Kubernetes: empaqueta un conjunto de
manifiestos como una unidad versionada (un *chart*), los parametriza con
una plantilla, y lleva un historial de qué versión de qué configuración
está corriendo en el clúster en cada momento.

Con `kubectl apply -f` sueltos, ninguna de esas tres cosas existe:
aplicar un manifiesto no dice qué versión es, no hay una forma nativa de
decir "estos 40 archivos son una sola cosa" y, sobre todo, no hay
`kubectl rollback`. En este proyecto eso se ve muy directo: la Sección 14
de la guía hace `helm rollback sa-platform 1` y el sistema entero —nueve
objetos de Kubernetes por microservicio, más Postgres, más RabbitMQ—
vuelve a un estado anterior con un solo comando. Reproducir eso con
manifiestos sueltos exigiría guardar copias de cada versión de cada
archivo a mano y volver a aplicarlos uno por uno, sin garantía de que la
combinación resultante sea consistente.

## 2. ¿Diferencia entre chart, release y repository?

Un **chart** es el paquete: la plantilla más los valores por defecto,
tal como vive en `charts/sa-platform/` en este repositorio. Es el
archivo fuente, no algo que corra en ningún lado todavía.

Un **release** es lo que existe cuando ese chart se instala en un
clúster con un nombre concreto: `helm install sa-platform charts/sa-platform`
crea el release `sa-platform` en el namespace `sa-p5`. El mismo chart
puede instalarse varias veces con nombres distintos (por ejemplo
`sa-platform-qa` en otro namespace) y cada instalación es un release
independiente con su propio historial de revisiones.

Un **repository** es donde se publican charts para que otros los
instalen por nombre en vez de por ruta local. `sa-platform` no está
publicado en ninguno (vive como carpeta local), pero sus dependencias sí:
`postgresql` y `rabbitmq` se bajan del repositorio de Bitnami
(`https://charts.bitnami.com/bitnami`) declarado en `Chart.yaml`.

## 3. ¿Qué es un StatefulSet y cuándo NO usarlo?

Un StatefulSet es el controlador para cargas de trabajo que necesitan
**identidad estable**: cada réplica tiene un nombre fijo y predecible
(`postgresql-0`, no un hash aleatorio), su propio PersistentVolumeClaim
que la sigue aunque el Pod se recree, y un orden garantizado de arranque
y apagado. Es lo que usa la dependencia de Bitnami para Postgres en este
chart: si `postgresql-0` muere, Kubernetes crea un Pod nuevo con el
**mismo nombre** y lo reconecta al **mismo** volumen (la Sección 15 de la
guía lo demuestra borrando el Pod y comprobando que los datos siguen
ahí).

No conviene usarlo para los microservicios de negocio (`gateway`,
`catalogo`, `inventario`, `pedidos`, `resenas`): ninguno guarda estado
propio en disco, cualquier réplica es intercambiable con cualquier otra,
y no importa en qué orden arranquen. Forzarlos a StatefulSet solo
agregaría restricciones (arranque secuencial, nombres fijos) sin ningún
beneficio, y complicaría el HPA: escalar un StatefulSet hacia abajo
siempre borra primero el índice más alto, mientras que un Deployment deja
que el scheduler elija libremente qué réplica quitar.

## 4. ¿Diferencia entre liveness, readiness y startup probe?

Las tres preguntan cosas distintas y una respuesta equivocada en
cualquiera de ellas produce un síntoma distinto:

- **startupProbe**: "¿ya terminó de arrancar?". Mientras falla,
  Kubernetes no evalúa ni liveness ni readiness. En `catalogo` e
  `inventario` se le dan hasta 20 intentos cada 3 segundos (60 segundos)
  porque esos procesos siembran datos de ejemplo al primer arranque; sin
  este margen, el liveness probe (más estricto) podría matar al
  contenedor **mientras todavía está arrancando**, antes de que tuviera
  oportunidad de terminar.
- **livenessProbe**: "¿sigue vivo, o quedó en un estado del que no puede
  salir solo?". Si falla, Kubernetes **reinicia el contenedor**. Es la
  red de seguridad contra deadlocks o fugas de memoria que dejan al
  proceso técnicamente corriendo pero sin poder responder nunca más.
- **readinessProbe**: "¿puede recibir tráfico *ahora mismo*?". Si falla,
  Kubernetes **no reinicia nada**: solo saca al Pod de los `Endpoints`
  del Service, así que deja de recibir peticiones nuevas hasta que vuelva
  a responder. Es lo que hace posible la actualización sin downtime de la
  Sección 20: un Pod nuevo no entra a servir tráfico hasta que su
  readiness pasa, y uno viejo se retira de la rotación en cuanto empieza
  a fallar, sin que eso cuente como un reinicio.

## 5. ¿Qué es una NetworkPolicy y por qué el tráfico es permitido por defecto?

Una NetworkPolicy es una regla que restringe qué tráfico de red puede
entrar (o salir) de los Pods que selecciona; sin ninguna definida, un
Pod acepta conexiones de cualquier otro Pod del clúster, sin importar el
namespace.

El tráfico es permitido por defecto porque Kubernetes nació pensado para
que los Pods se descubran y se hablen entre sí sin fricción —es
justamente lo que hace útil un Service—, y las NetworkPolicy son una
capa **opcional** que solo se activa si el plugin de red del clúster la
soporta (minikube con el addon de Calico o similar; el Ingress Controller
de NGINX no impone esto por sí solo, por lo que hay que verificar que el
CNI del clúster las aplique). El diseño de Kubernetes prioriza que
"nada roto por defecto" antes que "seguro por defecto"; asegurar la red
es una decisión explícita del operador, no una imposición de la
plataforma.

En este chart, la política `default-deny-ingress` (`networkpolicy-01`)
invierte esa regla para el namespace completo, y las políticas 02 a 05
son las excepciones puntuales (Ingress→gateway, gateway→microservicios,
microservicios→Postgres, pedidos y el Cronjob 2→RabbitMQ). La Sección 16
de la guía demuestra el bloqueo real: un Pod sin la etiqueta de gateway
no puede alcanzar a `catalogo`, aunque ambos estén en el mismo namespace
y el Service exista.

## 6. ¿Qué es un PodDisruptionBudget?

Un PodDisruptionBudget (PDB) le pone un límite a las interrupciones
**voluntarias** de un conjunto de Pods: cuántas réplicas como mínimo
deben seguir disponibles (o cuántas como máximo pueden faltar) mientras
alguien hace algo deliberado, como drenar un nodo para mantenimiento o
actualizar el clúster. Cada subchart de microservicio define
`minAvailable: 1`, así que si alguien intentara vaciar un nodo con
`kubectl drain` mientras solo queda una réplica sana de `catalogo`, el
drenado se bloquea hasta que haya otra réplica lista en otro nodo.

Es importante remarcar el límite: un PDB **no** protege contra caídas
involuntarias (un proceso que crashea, un nodo que se apaga solo). Para
eso están los probes y los reinicios automáticos del Deployment. El PDB
protege específicamente de que una operación humana planeada tumbe el
servicio por accidente.

## 7. ¿Qué ventajas y qué nuevos problemas introduce la comunicación asíncrona?

**Ventajas**, visibles en el flujo `pedidos-api` → RabbitMQ →
`pedidos-worker`: el productor responde al cliente HTTP de inmediato, sin
importar si el consumidor está lento, ocupado o caído (la Sección 17 de
la guía lo demuestra apagando el worker y viendo que crear un pedido
sigue devolviendo `201`). Esto desacopla el tiempo de vida de ambos
procesos y permite escalarlos por separado según su propia carga —la API
por tráfico HTTP, el worker por profundidad de cola—, en vez de que un
consumidor lento retrase directamente la respuesta al usuario.

**Problemas nuevos** que no existían en el flujo síncrono de la Práctica 4:

- **Entrega y duplicados.** Un mensaje puede reintentarse (si el ack se
  pierde en la red después de procesarlo pero antes de confirmarlo) y
  procesarse dos veces. El código de `pedidos-worker` no implementa
  deduplicación explícita; en un sistema real, escribir el resultado de
  forma idempotente (por ejemplo, con una clave única por evento) sería
  necesario.
- **Orden no garantizado** entre mensajes de colas distintas, y dificultad
  para razonar sobre "qué pasó primero" cuando algo falla, comparado con
  una pila de llamadas síncronas donde el orden es simplemente el orden
  del código.
- **Depuración más difícil.** Un error en el flujo síncrono aparece en el
  mismo request/response que lo causó. Un error en el consumidor aparece
  minutos después, en un proceso distinto, sin ninguna traza que lo
  conecte de vuelta a la petición HTTP original que lo generó.
- **Un componente más que puede fallar**: el broker mismo. Si RabbitMQ
  está caído, el código de `broker.js` está escrito para que publicar
  falle sin tumbar la petición HTTP (el pedido se guarda igual en
  Postgres), pero eso significa que la notificación asíncrona
  simplemente **se pierde** en ese caso, a diferencia de un mensaje que sí
  llegó a encolarse y solo espera a que el consumidor vuelva.

## 8. ¿Qué hace `helm rollback` internamente?

`helm rollback <release> <revision>` no "deshace" cambios ni guarda un
diff: Helm conserva el manifiesto **renderizado completo** de cada
revisión anterior (como un Secret en el namespace del release, uno por
revisión). Al hacer rollback a la revisión N, Helm toma ese manifiesto
completo ya guardado y lo aplica sobre el clúster como si fuera un
`helm upgrade` normal, comparándolo contra el estado actual para decidir
qué crear, actualizar o borrar.

Dos consecuencias prácticas de esto, visibles en `helm history` (Sección
14 de la guía): primero, un rollback **crea una revisión nueva** en el
historial (no borra las posteriores ni "regresa el contador"): si estabas
en la revisión 3 y vuelves a la 1, el historial pasa a tener una revisión
4 cuyo contenido es idéntico al de la 1. Segundo, el rollback solo puede
ser tan bueno como lo que Helm gestiona: si algo cambió *fuera* de Helm
directamente en el clúster (por ejemplo, alguien editó un Deployment con
`kubectl edit`), ese cambio no forma parte de ninguna revisión y el
rollback no lo revierte, porque Helm nunca supo que existió.
