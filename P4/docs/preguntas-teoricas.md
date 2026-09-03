# Preguntas teoricas

La rubrica asigna 15 puntos a responder de forma puntual y concisa sobre
microservicios, Docker y GraphQL, demostrando comprension **del sistema
entregado**. Aqui estan las respuestas ancladas a decisiones concretas de
este proyecto, no a definiciones genericas.

---

## Microservicios

**1. ¿Por que este sistema son microservicios y no un monolito repartido?**

Porque cada servicio se puede desplegar, reiniciar y escalar solo, tiene su
propia base de datos y no comparte modelos con los demas. La prueba practica
es el escenario 8 de la demostracion: detener `authz-service` no tumba el
resto del sistema, solo degrada las rutas que dependen de el. En un monolito
repartido, apagar una parte deja todo inservible.

**2. ¿Como se comunican los servicios?**

De dos formas. La normal es sincrona a traves del gateway: el navegador pide
`/api/pedidos` y el gateway reenvia. La segunda es directa entre servicios:
`pedidos-service` llama al `catalogo-service` por GraphQL para conocer el
precio vigente antes de guardar un pedido.

**3. ¿Por que pedidos no guarda una copia del menu?**

Guardar una copia obliga a mantener dos verdades sincronizadas. Si sube el
precio del latte en el catalogo y pedidos tiene su propia tabla, empieza a
cobrar precios viejos sin que nadie se entere. Preguntando en el momento del
pedido, el precio siempre es el vigente.

**4. Entonces, ¿por que `pedido_items` sí copia el nombre y el precio?**

Porque son datos distintos. El precio del catalogo es una **referencia**
(cambia). El precio que se cobro en un pedido de ayer es un **hecho
historico** (no puede cambiar). Copiarlo no es duplicar informacion: es
guardar lo que realmente ocurrio.

**5. ¿Que pasa si el catalogo esta caido cuando alguien pide?**

`pedidos-service` responde **503**, no crea el pedido. La alternativa seria
inventar un precio o usar uno cacheado, y ninguna es aceptable cuando se
trata de cobrar dinero.

**6. ¿Para que sirve el API Gateway si los servicios podrian exponerse solos?**

Concentra lo que de otro modo habria que repetir seis veces: verificar la
sesion, consultar el permiso, uniformar errores, registrar la bitacora. Y
deja una sola superficie publica: el navegador conoce una URL, no seis.

**7. ¿Por que la autenticacion y la autorizacion son servicios distintos?**

Responden preguntas distintas que cambian a ritmos distintos. *Quien eres*
depende del token y casi nunca cambia. *Que puedes hacer* es politica de
negocio y cambia seguido. Separarlas permite agregar un rol nuevo editando
un diccionario en `politicas.py`, sin volver a desplegar nada mas.

**8. Los microservicios confian en las cabeceras `X-Usuario-Rol`. ¿No es inseguro?**

Lo seria si fueran alcanzables desde fuera. En `docker-compose.yml` el unico
puerto que el sistema necesita publicar es el 8080 del edge; los demas estan
abiertos solo para calificar y en produccion se cierran. La confianza en las
cabeceras es valida exactamente mientras el gateway sea el unico camino, y
por eso los servicios criticos (inventario, moderacion de resenas) vuelven a
comprobar el rol por su cuenta: defensa en profundidad.

**9. ¿Por que un fallo de comunicacion devuelve 503 y no 403?**

Porque significan cosas distintas. 403 afirma que el usuario **no tiene**
permiso; 503 admite que **no se pudo comprobar**. Devolver 403 cuando el
servicio de autorizacion esta caido seria mentirle al usuario y ocultar una
falla de infraestructura detras de un problema de permisos.

**10. ¿Por que reintentos con espera creciente y no reintentos inmediatos?**

Un servicio saturado empeora si todos sus clientes reintentan a la vez. La
espera creciente (200 ms, 400 ms, 800 ms) le da margen para recuperarse y
evita convertir una caida corta en una tormenta de peticiones.

---

## Docker

**11. ¿Que hace exactamente `docker compose up --build`?**

Construye la imagen de cada servicio a partir de su Dockerfile, crea la red
`aroma`, arranca los contenedores respetando `depends_on` y los conecta por
nombre de servicio. Un solo comando levanta ocho contenedores.

**12. ¿Por que los servicios se llaman entre si por nombre y no por IP?**

Docker Compose corre un DNS interno en la red del proyecto: `postgres` o
`catalogo-service` resuelven al contenedor correspondiente. Las IP cambian
en cada reinicio; los nombres no.

**13. ¿Que diferencia hay entre `EXPOSE` y `ports`?**

`EXPOSE` en el Dockerfile es documentacion: dice en que puerto escucha el
proceso. `ports` en Compose publica ese puerto hacia el host. Un servicio
sin `ports` sigue siendo alcanzable dentro de la red interna, pero no desde
fuera de la maquina: asi quedaria todo salvo el edge en produccion.

**14. ¿Para que sirve el `healthcheck` y el `depends_on: condition: service_healthy`?**

`depends_on` a secas solo garantiza orden de arranque, no que el servicio
este listo. PostgreSQL tarda unos segundos en aceptar conexiones despues de
que el contenedor existe. Con `service_healthy`, los servicios esperan a que
`pg_isready` responda. Aun asi, cada servicio reintenta la conexion por su
cuenta: nunca se confia en un solo mecanismo.

**15. ¿Por que un volumen para PostgreSQL?**

Sin volumen, los datos viven en la capa de escritura del contenedor y se
pierden con `docker compose down`. Con el volumen `datos-postgres`, las
cuentas y los pedidos sobreviven a los reinicios. Para empezar de cero:
`docker compose down -v`.

**16. ¿Por que las imagenes son `alpine` y `slim`?**

Menos peso y menos superficie: menos paquetes instalados son menos
vulnerabilidades potenciales y descargas mas rapidas.

**17. ¿Por que se copia `package.json` antes que el codigo?**

Por la cache de capas de Docker. Si el codigo cambia pero las dependencias
no, Docker reutiliza la capa de `npm install` y la reconstruccion baja de
minutos a segundos.

**18. ¿Por que hay un `.dockerignore`?**

Para que `.venv/`, `node_modules/` y `.env` no entren en la imagen. Ademas
de peso inutil, meter un `.env` en una imagen es filtrar secretos.

---

## GraphQL

**19. ¿Que resuelve GraphQL aqui que REST no resolvia igual de bien?**

El menu. La pantalla necesita categorias y productos anidados; en REST eso
son dos llamadas (`/categorias` y `/productos`) o un endpoint a la medida.
En GraphQL el cliente pide en una sola consulta exactamente los campos que
va a pintar.

**20. ¿Por que hay un solo endpoint `/graphql` para leer y escribir?**

Es el modelo de GraphQL: un unico punto de entrada donde el documento
enviado dice si es `query` o `mutation`.

**21. Entonces, ¿como se controlan los permisos si todo entra por la misma URL?**

En dos niveles. El gateway concede un permiso de grano grueso por endpoint
(`catalogo:usar`). El grano fino vive en el resolver: `crearProducto` y
`cambiarDisponibilidad` exigen rol Admin y responden `FORBIDDEN` a un
Cliente. Es una diferencia real con REST, donde el metodo HTTP y la ruta ya
distinguen leer de escribir y el gateway puede decidir solo.

**22. ¿Que son los resolvers?**

Las funciones que producen el valor de cada campo. `Producto.categoria` es
un resolver: cuando la consulta pide la categoria de un producto, GraphQL lo
ejecuta. Por eso el esquema puede exponer relaciones sin que el cliente sepa
de que tabla salen.

**23. ¿Que es el problema N+1 y aparece en este proyecto?**

Aparece: pedir 10 productos con su categoria dispara 1 consulta para los
productos y 10 para las categorias, porque el resolver de `categoria` se
ejecuta una vez por producto. Con este volumen de datos no se nota. La
solucion estandar es un `DataLoader`, que agrupa los identificadores de un
mismo ciclo y hace una sola consulta.

**24. ¿Por que GraphQL devuelve 200 con errores dentro del cuerpo?**

Porque una consulta puede resolver unos campos y fallar en otros: el
resultado es parcial, no fallido. Por eso el cliente
(`frontend/api.js`) revisa siempre el arreglo `errors` aunque el codigo HTTP
sea 200. Los errores de sesion y permiso si son HTTP, porque los genera el
gateway antes de que GraphQL vea la peticion.

**25. ¿Por que se usaron dos lenguajes distintos?**

Es requisito de la practica, y la arquitectura lo permite sin costo: los
servicios se comunican por HTTP y JSON, no por tipos compartidos. Node.js
para catalogo y pedidos (mucha E/S, poca logica), Python para inventario y
resenas (aritmetica de existencias, agregaciones) y para heredar sin cambios
el modulo de autenticacion de la Practica 2.
