# Costos y procedimiento de eliminación

## Estimación de costos (referencia, revisar precios actuales de DigitalOcean)

Este despliegue usa recursos que se facturan **por el tiempo que
existen**, no por el tráfico que reciben. La siguiente tabla usa el
tamaño de nodo que realmente se usó en este despliegue
(`s-1vcpu-2gb`, más pequeño que el sugerido inicialmente en la guía,
suficiente para el sistema en reposo); los precios exactos cambian con
el tiempo y conviene revisarlos en la
[calculadora de precios de DigitalOcean](https://www.digitalocean.com/pricing/kubernetes)
antes de dejar el clúster corriendo por periodos largos.

| Recurso | Cantidad | Costo aproximado |
|---|---|---|
| Nodo `s-1vcpu-2gb` (1 vCPU, 2 GB) | 2 | ~ USD 0.009/hora c/u → ~ USD 0.018/hora total |
| Plano de control de DOKS | 1 | **Gratis** (a diferencia de GKE, DigitalOcean no cobra por el plano de control) |
| Volumen persistente (Postgres 2Gi + RabbitMQ 2Gi) | 2 | ~ USD 0.10/GB-mes → una fracción de centavo por hora |
| Load Balancer (creado por el Service del gateway) | 1 | ~ USD 0.017/hora (~USD 12/mes) |
| Container Registry (DOCR, plan `basic`) | 1 | ~ USD 5/mes fijos, independiente de las horas del clúster |

**Total aproximado mientras el clúster está arriba: ~ USD 0.04-0.05 por
hora**, más el cargo fijo mensual del registro (~USD 5/mes) y del Load
Balancer si se prorratea por horas (~USD 12/mes completo). El nodo en sí
es el rubro más barato de los cuatro — el Load Balancer y el registro
pesan proporcionalmente más en un despliegue de este tamaño.

Revisa si tu cuenta tiene disponible algún crédito de bienvenida o
educativo (por ejemplo, a través del GitHub Student Developer Pack);
las condiciones cambian con frecuencia y no se documentan aquí montos
específicos para no quedar desactualizados.

## Ajuste real hecho durante el despliegue: node pool de 1 a 2

Al crear el clúster con `--count 1` (para minimizar costo), un segundo
Pod de `catalogo` quedó indefinidamente en estado `Pending`: un solo
nodo `s-1vcpu-2gb` no tenía capacidad para Postgres + RabbitMQ + los 6
servicios con sus réplicas del HPA. Se escaló a 2 nodos con:

```powershell
doctl kubernetes cluster node-pool update aroma-p6 aroma-p6-default-pool --count 2
```

La lección de costos aquí: el requisito de "al menos 2 nodos" de la
rúbrica no es solo un formalismo — con 1 nodo el sistema literalmente no
cabe. Dimensionar por debajo del mínimo no ahorra dinero de forma útil,
solo cambia dónde aparece el problema (de "más caro" a "no funciona").

## Cómo reducir el costo si hace falta dejarlo corriendo más tiempo

- El tamaño `s-1vcpu-2gb` x 2 ya es el piso razonable para este sistema;
  bajar más resulta en pods `Pending` como el que se documentó arriba.
- Reducir el tamaño de los volúmenes (`size: 1Gi` en vez de `2Gi`) si no
  se va a generar mucho volumen de datos de prueba.
- Escalar el node pool a un tamaño menor temporalmente con
  `doctl kubernetes cluster node-pool update ... --count 1` en vez de
  eliminar el clúster completo, si solo se necesita pausar por unas
  horas — aunque, como se documentó arriba, con 1 nodo el sistema deja
  de tener capacidad suficiente y algunos pods quedarán `Pending` hasta
  que se vuelva a escalar a 2.
- Usar el plan `starter` de DOCR en vez de `basic` si las imágenes caben
  en su límite de almacenamiento más reducido (500 MiB; las 6 imágenes
  de este proyecto pesan más que eso, así que en la práctica hizo falta
  `basic`).

## Costo oculto a vigilar: reglas de firewall manuales

Durante el despliegue, el firewall administrado por DOKS
(`k8s-public-access-...`) no sincronizó automáticamente el `NodePort`
del Service del gateway, y hubo que abrirlo a mano:

```powershell
doctl compute firewall add-rules <firewall-id> --inbound-rules "protocol:tcp,ports:<nodeport>,address:0.0.0.0/0"
```

Esto no genera costo adicional (los firewalls de DigitalOcean son
gratuitos), pero **si se borra el clúster y se crea uno nuevo más
adelante, el `NodePort` va a ser distinto** y esta regla manual va a
quedar apuntando a un puerto que ya no es el correcto. No es una regla
"que sobreviva" al recrear el clúster de forma útil — hay que repetir
este paso cada vez que se reinstale desde cero contra un clúster nuevo.

## Procedimiento de eliminación (al finalizar la práctica)

Orden recomendado: primero lo que vive **dentro** del clúster (para que
Kubernetes le avise a DigitalOcean que debe liberar el Load Balancer de
forma ordenada), y al final el clúster y el registro.

```powershell
# 1. Desinstalar el release de Helm (borra Deployments, Services -> esto
#    le avisa a DigitalOcean que debe liberar el Load Balancer)
helm uninstall sa-platform -n sa-p6

# 2. Esperar a que el Load Balancer se libere (puede tardar 1-2 minutos)
kubectl get svc -n sa-p6
#    repetir hasta que el comando ya no encuentre el Service del gateway

# 3. Borrar el namespace (por si quedo algun objeto suelto)
kubectl delete namespace sa-p6

# 4. Borrar el cluster de DOKS completo (nodos + plano de control).
#    Esto tambien elimina el firewall "k8s-public-access-..." que DOKS
#    administra automaticamente (incluida la regla manual del NodePort
#    que se agrego durante el despliegue): no hace falta borrarla aparte.
doctl kubernetes cluster delete aroma-p6 --force

# 5. Borrar el registro de DOCR (opcional, pero evita dejar
#    almacenamiento facturable olvidado)
doctl registry delete aroma --force

# 6. Verificar que no quede ningun volumen huerfano
#    (a veces un PVC borrado a la fuerza deja el Volume de DigitalOcean
#    sin reclamar; revisar y borrar manualmente si aparece algo aqui)
doctl compute volume list

# 7. Verificar que no quede ningun firewall huerfano
doctl compute firewall list
```

**Confirmación final**: en la consola de DigitalOcean, la sección
*Kubernetes* debe quedar vacía, *Container Registry* no debe mostrar el
registro `aroma`, *Volumes* no debe mostrar ningún disco relacionado con
`postgresql` o `rabbitmq`, y *Networking → Firewalls* no debe mostrar
ningún firewall con el nombre del clúster. Captura de pantalla de esas
cuatro pantallas vacías es la evidencia de limpieza que pide el
entregable (ver `plantilla-evidencias.md`, sección 9).
