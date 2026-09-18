# Guion para el momento de calificación — Práctica 6

Documento de uso **solo durante la sesión de calificación**: un comando
por criterio de la rúbrica, en el mismo orden en que aparece, con lo
que debe verse para considerarlo cumplido. No es la documentación
formal (ver `README.md`) — es la chuleta operativa para no tener que
buscar nada en el momento.

**Antes de empezar la sesión**, corre esto una sola vez:

```powershell
cd "C:\ruta\a\Practicas-SA-B-202103763\P6"
doctl kubernetes cluster kubeconfig save aroma-p6
$IP = kubectl get svc -n sa-p6 sa-platform-gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
Write-Host "IP publica: $IP"
```

Si `$IP` sale vacío o distinto al que tienes documentado, es porque el
clúster se recreó — solo actualiza el valor en `README.md` sección 4
antes de la sesión.

---

## 8.1 Requisitos previos (Sí/No)

| Requisito | Comando | Qué debe verse |
|---|---|---|
| Clúster en la nube, no local | `kubectl config current-context` | Debe decir `do-nyc1-aroma-p6` (o similar con "do-"), nunca `minikube` |
| Acceso público | `Invoke-RestMethod -Uri "http://${IP}:8000/api/salud"` | JSON con `"estado":"arriba"` |
| Documentación en Markdown | — | Mostrar `README.md` abierto |
| Comunicación asíncrona gateway↔microservicio | Ver sección "Comunicación asíncrona" más abajo | Filas reales en `auditoria_gateway` |

---

## 1. Habilidades (40 pts)

### 1.1 — Creación y configuración del clúster (10 pts)

```powershell
kubectl get nodes -o wide
```

**Debe verse:** al menos 2 nodos en `STATUS: Ready`, con IPs reales
(no `127.0.0.1` ni direcciones internas de un contenedor Docker).

---

### 1.2 — Publicación de imágenes en el registro (10 pts)

```powershell
doctl registry repository list-v2 aroma
```

**Debe verse:** 5 repositorios (`gateway`, `catalogo-service`,
`inventario-service`, `pedidos-service`, `resenas-service`), con
`pedidos-service` mostrando `Tag Count: 2` (una es
`cronjob-resumen-1.0.0`, la sexta imagen compartiendo repositorio —
explicar esto si preguntan, está documentado en `README.md` sección 3,
paso 3).

---

### 1.3 — Despliegue de la plataforma en la nube (10 pts)

```powershell
kubectl get pods -n sa-p6 -o wide
```

**Debe verse:** los 8 componentes (`postgresql-0`, `rabbitmq-0`,
`sa-platform-gateway-*`, `sa-platform-catalogo-*`,
`sa-platform-inventario-*`, `sa-platform-pedidos-api-*`,
`sa-platform-pedidos-worker-*`, `sa-platform-resenas-*`) en
`1/1 Running`, repartidos entre los nodos (columna `NODE`).

Si algo no está `Running`, no entrar en pánico: correr de nuevo el
mismo comando una vez más antes de asumir que hay un problema —
varios pods de este sistema se autorepararon solos durante el
desarrollo tras una simple demora de red.

---

### 1.4 — Exposición pública del sistema (10 pts)

```powershell
Invoke-RestMethod -Uri "http://${IP}:8000/api/salud"
```

**Debe verse:** JSON con `"estado":"arriba"` y los 4 microservicios
detrás del gateway también `"arriba"`. Mencionar en voz alta que
`${IP}` es una dirección pública real de DigitalOcean, no `localhost`
— abrir la misma URL en el navegador si se quiere reforzar
visualmente.

Prueba adicional recomendada (impacta también en 2.2):

```powershell
Invoke-RestMethod -Uri "http://${IP}:8000/api/catalogo/graphql" -Method Post `
  -ContentType "application/json" -Body '{"query":"{ productos { id nombre precio } }"}'
```

---

## 2. Conocimiento (60 pts)

### 2.1 — Adaptación a la nube: almacenamiento, red y secretos (15 pts)

**Almacenamiento:**

```powershell
kubectl get pvc -n sa-p6 -o jsonpath='{.items[*].spec.storageClassName}'
```

Debe decir `do-block-storage do-block-storage`.

**Secretos (sin versionar):**

```powershell
kubectl get secrets -n sa-p6
```

Señalar `sa-platform-catalogo`, `sa-platform-gateway`,
`sa-platform-pedidos`, etc. — explicar que las credenciales viven ahí,
no en el repositorio. Si quieren ver el valor real decodificado:

```powershell
$valor = kubectl get secret sa-platform-catalogo -n sa-p6 -o jsonpath='{.data.DATABASE_URL}'
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($valor))
```

**Red (`NetworkPolicy` bloqueando tráfico lateral):**

```powershell
kubectl run sonda --image=busybox:1.36 -n sa-p6 --rm -it --restart=Never -- `
  wget -qO- --timeout=5 http://sa-platform-catalogo:4001/salud
```

**Debe verse:** falla por tiempo de espera agotado (`wget: download
timed out`). Esto es lo que se quiere mostrar — un pod cualquiera del
namespace no puede saltarse al gateway y llegar directo a un
microservicio interno.

---

### 2.2 — Evidencias de funcionamiento (15 pts)

Mostrar directamente:
- Consola web de DigitalOcean → *Kubernetes* → `aroma-p6` (clúster y
  nodos).
- Consola web → *Container Registry* → `aroma` (las imágenes).
- El resultado en vivo del comando de la sección 1.4 (petición desde
  internet).
- Las capturas ya incorporadas en `README.md` sección 6.2 / carpeta
  `docs/capturas/`, por si el clúster llegara a fallar justo durante la
  sesión y hiciera falta mostrar evidencia grabada en vez de en vivo.

---

### 2.3 — Preguntas teóricas (20 pts)

No requiere demostración en vivo. Abrir `README.md`, sección 9
(las 5 preguntas completas). Si preguntan sobre alguna en particular,
la más rica en detalle real es la **9.2** (LoadBalancer): documenta el
diagnóstico real de tres capas (Service → firewall → puerto) que
ocurrió durante el desarrollo.

---

### 2.4 — Gestión de costos y eliminación de recursos (10 pts)

Mostrar `README.md` sección 7 (costo aproximado, con el tamaño de nodo
realmente usado) y sección 8 (procedimiento de eliminación completo).

**No ejecutar los comandos de eliminación durante la calificación** —
son para después de que termine la sesión. Si quien califica pide
confirmar que el procedimiento es válido, basta con leerlo en voz alta
y señalar que ya se usó una vez antes (o se usará al finalizar) sin
necesidad de correrlo ahí mismo.

---

## Comunicación asíncrona gateway↔microservicio (requisito de esta práctica)

Esta es la demostración más vistosa — vale la pena hacerla completa:

```powershell
# 1. Genera una peticion real
Invoke-RestMethod -Uri "http://${IP}:8000/api/catalogo/graphql" -Method Post `
  -ContentType "application/json" -Body '{"query":"{ productos { id } }"}'

# 2. Muestra que el gateway la publico y pedidos-worker la guardo de forma independiente
kubectl exec -n sa-p6 postgresql-0 -- env PGPASSWORD='TU_CLAVE_REAL' psql -U aroma -d pedidos_db `
  -c "SELECT metodo, ruta, publicado_en FROM auditoria_gateway ORDER BY id DESC LIMIT 5;"
```

**Debe verse:** la fila más reciente con la hora coincidiendo con la
petición que se acaba de hacer — la prueba de que el flujo es real, no
solo código sin ejecutar.

(Reemplaza `TU_CLAVE_REAL` por la contraseña real de
`values-secretos-cloud.yaml` antes de la sesión, para no tener que
buscarla en el momento.)

---

## Si algo falla durante la sesión en vivo

| Síntoma | Qué decir/hacer |
|---|---|
| Un pod muestra `CrashLoopBackOff` o `0/1` | Correr `kubectl get pods -n sa-p6` de nuevo — varios componentes de este sistema se autoreparan tras un reinicio transitorio, documentado en `README.md`. Si persiste, mostrar las capturas ya guardadas como respaldo. |
| `$IP` no responde | Verificar `kubectl get svc -n sa-p6 sa-platform-gateway` — si `EXTERNAL-IP` cambió, actualizar `$IP` y reintentar. |
| El clúster no conecta (`kubectl` da error de conexión) | Repetir `doctl kubernetes cluster kubeconfig save aroma-p6` — soluciona el 90% de los casos. |
| Quieren ver algo que ya no se puede probar en vivo (p. ej. porque ya se eliminó el clúster) | Usar las capturas de `docs/capturas/` y el historial de comandos ya documentado en `README.md` — la rúbrica pide evidencia, no necesariamente que se repita en vivo. |
