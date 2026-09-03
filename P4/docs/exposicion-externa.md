# Salida al exterior del frontend

## Como esta resuelto en esta entrega

La practica exige Docker Compose, no Kubernetes. En Compose, el unico
componente con un puerto publicado hacia el mundo es el contenedor `edge`
(nginx):

```yaml
edge:
  ports:
    - "8080:80"
```

Ese contenedor hace dos cosas:

1. Sirve los archivos estaticos del frontend.
2. Reenvia todo lo que empiece con `/api/` al API Gateway.

La consecuencia importante es que **el frontend y la API comparten origen**
(`http://localhost:8080`). Gracias a eso:

- El navegador envia la cookie de sesion sin configuracion de CORS.
- La cookie sigue siendo `HttpOnly`, es decir, invisible para JavaScript.
- Ningun microservicio necesita estar expuesto: el gateway es la unica
  puerta y el edge es el unico portal.

## Equivalencia con Kubernetes

Si este mismo sistema se moviera a un cluster, el `edge` seria reemplazado
por uno de estos dos objetos:

| Opcion | Cuando conviene | Que hace |
|---|---|---|
| `Service` tipo `LoadBalancer` | Un solo dominio y un solo sistema en el cluster. Es la mas directa. | El proveedor de nube crea un balanceador con IP publica que apunta a los pods del frontend/gateway. |
| `Ingress` | Varios sistemas comparten el cluster, o hace falta TLS, rutas por path y hosts virtuales. | Un controlador (nginx-ingress, Traefik) enruta por host y ruta hacia distintos `Service` internos. |

En la practica se suelen combinar: el `Ingress` publica el sistema y el
controlador de ingress se expone con un `Service` de tipo `LoadBalancer`.

En `k8s/` estan los dos manifiestos de ejemplo, incluidos como referencia de
diseno. No forman parte de lo que se levanta con `docker compose up`.

## Regla que no cambia entre ambas formas

Sea con Compose, con `LoadBalancer` o con `Ingress`, la regla es la misma:

> Un unico punto de entrada publico. Los microservicios solo son alcanzables
> desde la red interna, y solo a traves del API Gateway.

Es lo que permite que los servicios de negocio confien en las cabeceras
`X-Usuario-Id` y `X-Usuario-Rol` que inyecta el gateway. Si un microservicio
tuviera IP publica, cualquiera podria falsificar esas cabeceras y saltarse
la autenticacion por completo.
