# Tamaño de imágenes: antes y después del multi-stage build

La rúbrica pide una tabla comparativa real. No se puede fabricar aquí
porque el tamaño depende de tu Docker Desktop, tu versión de las bases
`node:20-alpine` / `python:3.11-slim` en el momento en que construyas, y
de si ya las tenías descargadas. Este documento trae la tabla vacía y el
procedimiento exacto para llenarla en dos minutos.

## Procedimiento

**1. Construir la version "antes" (single-stage, sin optimizar).**

Cada carpeta de servicio ya tiene el Dockerfile multi-stage optimizado
(el que se usa en el chart). Para comparar, construye también una versión
de referencia sin multi-stage. El ejemplo siguiente usa `catalogo-service`;
repite el patrón (una sola etapa `FROM ... COPY . . RUN install CMD`) para
los demás si quieres la tabla completa.

```powershell
cd P5\services\catalogo-service

@"
FROM node:20-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY src ./src
EXPOSE 4001
CMD ["node", "src/index.js"]
"@ | Out-File -Encoding utf8 Dockerfile.antes

docker build -t aroma/catalogo-service:antes -f Dockerfile.antes .
docker build -t aroma/catalogo-service:1.0.0 -f Dockerfile .
```

**2. Medir.**

```powershell
docker images aroma/catalogo-service --format "table {{.Tag}}\t{{.Size}}"
```

**3. Repetir para los demás servicios** (gateway, inventario, pedidos-service,
pedidos-worker, resenas-service) cambiando solo la carpeta y, para los
servicios Python, el Dockerfile de referencia:

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
EXPOSE 4002
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "4002"]
```

## Tabla a completar

| Servicio | Imagen "antes" (single-stage) | Imagen "después" (multi-stage) | Reducción |
|---|---|---|---|
| gateway | ___ MB | ___ MB | ___ % |
| catalogo-service | ___ MB | ___ MB | ___ % |
| inventario-service | ___ MB | ___ MB | ___ % |
| pedidos-service | ___ MB | ___ MB | ___ % |
| resenas-service | ___ MB | ___ MB | ___ % |
| cronjob-resumen | ___ MB | (no aplica: no tiene version "antes") | — |

## Qué explica la diferencia (y qué no)

En los servicios **Node.js**, la reducción real viene de dos cosas: el
multi-stage descarta `npm cache` y cualquier archivo de la etapa de
build que no sea `node_modules`, y `npm install --omit=dev` ya excluye
`devDependencies` en ambas versiones (esa parte no es mérito del
multi-stage, es buena práctica de por sí). La diferencia que sí aporta el
multi-stage es que ninguna capa intermedia con caché de npm queda en la
imagen final: aunque la capa se "descarte" conceptualmente, en un
Dockerfile de una sola etapa esa capa igual queda en el historial de la
imagen.

En los servicios **Python**, la diferencia es más modesta porque
`psycopg[binary]` ya usa una wheel precompilada: no hace falta `gcc` ni
`build-essential` para instalar las dependencias en ningún escenario, así
que no hay herramientas de compilación que el multi-stage pueda eliminar.
La ganancia aquí es menor y es honesto decirlo en el reporte en vez de
inflar la comparación.

Anota esta explicación (o tu propia medición, que puede matizarla) en la
columna de análisis de tu documento final.
