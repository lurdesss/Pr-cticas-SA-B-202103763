# Manifiestos de Kubernetes (referencia)

Esta carpeta **no se usa** para levantar la practica: el sistema corre con
`docker compose up --build`.

Se incluye porque el frontend necesita una salida al exterior y esa salida
cambia de forma segun donde se despliegue. Aqui queda documentado como se
veria la misma decision arquitectonica en un cluster:

- `01-edge-loadbalancer.yaml` — el edge publicado con un `Service` de tipo
  `LoadBalancer`; los microservicios quedan como `ClusterIP`.
- `02-edge-ingress.yaml` — la variante con `Ingress` y TLS.

La explicacion esta en [../docs/exposicion-externa.md](../docs/exposicion-externa.md).

Con `docker compose`, el papel de balanceador lo cumple el contenedor
`edge`, que es el unico con un puerto publicado.
