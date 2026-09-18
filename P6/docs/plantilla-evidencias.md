# Plantilla de evidencias — Práctica 6

Documento para armar el entregable final. Cada sección corresponde a un
punto específico de la rúbrica, con el comando exacto para generar la
evidencia y un espacio para pegar la captura de pantalla o la salida de
texto. Sustituye cada bloque `[PEGAR AQUÍ ...]` por tu captura real
antes de entregar.

Convención para las capturas: guárdalas en una carpeta
`docs/capturas/` con nombres descriptivos (`01-nodos.png`,
`02-registro.png`, etc.) y referéncialas con Markdown:
`![descripción](capturas/01-nodos.png)`.

---

## 1. Creación y configuración del clúster (10 pts — Habilidades)

**Comando:**

```powershell
kubectl get nodes -o wide
```

**Qué debe mostrar:** exactamente 2 nodos (o más) en estado `Ready`,
con sus IPs internas y externas.

[PEGAR AQUÍ la salida de `kubectl get nodes -o wide`]

**Captura de la consola web:** DigitalOcean → *Kubernetes* → tu clúster
→ pestaña de nodos, mostrando el mismo conteo y estado.

[PEGAR AQUÍ la captura de pantalla de la consola]

---

## 2. Publicación de imágenes en el registro (10 pts — Habilidades)

**Comando:**

```powershell
doctl registry repository list-v2 aroma
```

**Qué debe mostrar:** 5 repositorios (`gateway`, `catalogo-service`,
`inventario-service`, `pedidos-service`, `resenas-service`), con
`pedidos-service` mostrando 2 etiquetas distintas (`1.0.0` y
`cronjob-resumen-1.0.0`) y `Tag Count: 2`.

[PEGAR AQUÍ la salida de `doctl registry repository list-v2 aroma`]

**Captura de la consola web:** DigitalOcean → *Container Registry* →
`aroma`, mostrando los 5 repositorios.

[PEGAR AQUÍ la captura de pantalla de la consola]

---

## 3. Despliegue de la plataforma en la nube (10 pts — Habilidades)

**Comando:**

```powershell
kubectl get pods -n sa-p6 -o wide
```

**Qué debe mostrar:** todos los pods de los 6 servicios propios (más
`postgresql-0` y `rabbitmq-0`) en `1/1 Running`, repartidos entre los
nodos disponibles.

[PEGAR AQUÍ la salida de `kubectl get pods -n sa-p6 -o wide`]

---

## 4. Exposición pública del sistema (10 pts — Habilidades)

**Comando (PowerShell nativo, evita problemas de escape con `curl.exe`):**

```powershell
$IP = kubectl get svc -n sa-p6 sa-platform-gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
Invoke-RestMethod -Uri "http://${IP}:8000/api/salud"
```

**Qué debe mostrar:** JSON con `"estado":"arriba"` y el detalle de los
4 microservicios detrás del gateway, todos también `"arriba"`.

[PEGAR AQUÍ la salida del `Invoke-RestMethod`]

**Evidencia reforzada (recomendada):** la misma petición hecha **desde
una red distinta** (datos móviles del celular, o el navegador de otra
persona), para demostrar que el acceso es realmente público y no un
efecto de estar en la misma red que el clúster.

[PEGAR AQUÍ captura desde el celular o desde otra red]

---

## 5. Adaptación a la nube: almacenamiento, red y secretos (15 pts — Conocimiento)

### 5.1 Almacenamiento — StorageClass del proveedor

```powershell
kubectl get pvc -n sa-p6 -o jsonpath='{.items[*].spec.storageClassName}'
```

Debe mostrar `do-block-storage do-block-storage` (uno por cada PVC de
Postgres y RabbitMQ).

[PEGAR AQUÍ la salida]

### 5.2 Secretos — credenciales fuera del repositorio

```powershell
kubectl get secrets -n sa-p6

$valor = kubectl get secret sa-platform-catalogo -n sa-p6 -o jsonpath='{.data.DATABASE_URL}'
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($valor))
```

El segundo comando muestra la cadena de conexión real, confirmando que
la contraseña vive en un objeto `Secret` gestionado por Kubernetes/Helm
y nunca estuvo en el repositorio (solo en `values-secretos-cloud.yaml`,
que está en `.gitignore` — puedes mostrar tu `.gitignore` como evidencia
complementaria).

[PEGAR AQUÍ ambas salidas]

### 5.3 Red — NetworkPolicy funcionando de verdad

```powershell
# Desde un pod SIN la etiqueta de gateway: debe fallar
kubectl run sonda --image=busybox:1.36 -n sa-p6 --rm -it --restart=Never -- `
  wget -qO- --timeout=5 http://sa-platform-catalogo:4001/salud
```

Esta prueba concreta demuestra que el aislamiento de red del chart
(heredado de la Práctica 5) sigue vigente en la nube: solo el gateway
puede llegar a los microservicios internos, ni siquiera un pod cualquiera
del mismo namespace puede saltárselo.

[PEGAR AQUÍ la salida — debe fallar por timeout]

---

## 6. Evidencias de funcionamiento (15 pts — Conocimiento)

### 6.1 Consola del proveedor — Load Balancer

DigitalOcean → *Networking* → *Load Balancers* → el que se creó
automáticamente al desplegar el `Service` del gateway.

[PEGAR AQUÍ la captura]

### 6.2 Consola del proveedor — Volumes

DigitalOcean → *Volumes* → los 2 discos de Postgres y RabbitMQ.

[PEGAR AQUÍ la captura]

### 6.3 Petición exitosa desde internet (repetida aquí para el conjunto de evidencias de funcionamiento)

[PEGAR AQUÍ la misma captura de la sección 4, o una nueva]

---

## 7. Comunicación asíncrona entre microservicios y api gateway (requisito de esta práctica)

Esta es la evidencia más específica de esta práctica en particular — no
basta con mostrar que el sistema responde, hay que mostrar el flujo
asíncrono en sí.

### 7.1 El gateway publicando eventos (flujo nuevo, gateway → RabbitMQ → pedidos-worker)

```powershell
# Genera un poco de trafico real
Invoke-RestMethod -Uri "http://${IP}:8000/api/catalogo/graphql" -Method Post `
  -ContentType "application/json" -Body '{"query":"{ productos { id } }"}'

# Verifica que el gateway publico el evento y pedidos-worker lo guardo
kubectl exec -n sa-p6 postgresql-0 -- env PGPASSWORD='TU_CLAVE_REAL' psql -U aroma -d pedidos_db `
  -c "SELECT metodo, ruta, publicado_en FROM auditoria_gateway ORDER BY id DESC LIMIT 5;"
```

**Qué debe mostrar:** filas reales, con la más reciente coincidiendo con
la petición que acabas de hacer (compara la hora).

[PEGAR AQUÍ la salida de la consulta `SELECT ... FROM auditoria_gateway`]

### 7.2 El flujo heredado de P5, con el consumidor caído (pedidos → RabbitMQ → pedidos-worker)

```powershell
kubectl scale deployment/sa-platform-pedidos-worker -n sa-p6 --replicas=0

Invoke-RestMethod -Uri "http://${IP}:8000/api/pedidos" -Method Post `
  -ContentType "application/json" -Body '{"items":[{"productoId":"1","cantidad":1}]}'

kubectl scale deployment/sa-platform-pedidos-worker -n sa-p6 --replicas=1
Start-Sleep -Seconds 15
kubectl logs -n sa-p6 deployment/sa-platform-pedidos-worker --tail=10
```

**Qué debe mostrar:** el pedido se crea (`201`) aunque el consumidor
esté apagado, y al reactivarlo el log muestra `[worker] pedido #...
notificado` — demuestra que el productor nunca esperó al consumidor.

[PEGAR AQUÍ el log de `pedidos-worker`]

---

## 8. Preguntas teóricas (20 pts — Conocimiento)

Ver **[preguntas-teoricas.md](preguntas-teoricas.md)**. No requiere
evidencia adicional aquí; solo confirma que las 5 respuestas quedaron
completas antes de entregar.

---

## 9. Gestión de costos y eliminación de recursos (10 pts — Conocimiento)

Ver **[costos-y-limpieza.md](costos-y-limpieza.md)** para el desglose de
costos. La evidencia de eliminación se genera **al final**, cuando ya
terminaste de calificar/entregar:

```powershell
helm uninstall sa-platform -n sa-p6
kubectl delete namespace sa-p6
doctl kubernetes cluster delete aroma-p6 --force
doctl registry delete aroma --force
```

Después, capturas de las 4 pantallas vacías en la consola web:

[PEGAR AQUÍ: Kubernetes → sin clústeres]

[PEGAR AQUÍ: Container Registry → sin registro "aroma"]

[PEGAR AQUÍ: Volumes → sin discos de postgresql/rabbitmq]

[PEGAR AQUÍ: Networking → Firewalls → sin el firewall del clúster]

```powershell
doctl kubernetes cluster list
doctl compute volume list
doctl compute firewall list
```

[PEGAR AQUÍ la salida de los tres comandos, confirmando listas vacías o sin referencias a "aroma-p6"]

---

## Checklist final antes de entregar

- [ ] Las 4 evidencias marcadas como "primera/segunda/tercera/cuarta evidencia" en `GUIA-NUBE.md` están todas capturadas
- [ ] Las capturas de consola web (clúster, registro, Load Balancer, Volumes) están incluidas
- [ ] La prueba de NetworkPolicy (sección 5.3) muestra el bloqueo real
- [ ] La tabla `auditoria_gateway` tiene filas reales, no vacía
- [ ] Las 5 preguntas teóricas están completas y en tus propias palabras
- [ ] El procedimiento de limpieza está documentado con sus comandos, aunque los recursos ya se hayan eliminado al momento de entregar
- [ ] Ningún archivo de este repositorio contiene una contraseña real (revisa `values-secretos-cloud.yaml` NO esté en el commit: `git status` no debe mostrarlo)
