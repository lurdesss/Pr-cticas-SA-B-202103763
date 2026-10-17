# Multi-stage: la etapa "dependencias" instala node_modules con las
# herramientas de compilacion que hagan falta; la etapa final solo copia
# el resultado. Nada de cache de npm, manifiestos de build ni devDependencies
# viaja a la imagen que se ejecuta.

# ---------------------------------------------------------------- build
FROM node:20-alpine AS dependencias
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

# -------------------------------------------------------------- runtime
FROM node:20-alpine AS runtime
WORKDIR /app

# Usuario sin privilegios: en la Practica 4 el proceso corria como root
# (arranque por defecto de la imagen node). Aqui se crea un usuario
# dedicado para satisfacer runAsNonRoot desde el propio Dockerfile, no
# solo desde el securityContext de Kubernetes.
RUN addgroup -S aroma && adduser -S aroma -G aroma

COPY --from=dependencias /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

USER aroma

EXPOSE 4003
HEALTHCHECK --interval=10s --timeout=3s --retries=6 --start-period=15s \
  CMD node -e "fetch('http://127.0.0.1:4003/salud').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
# P10: el SDK de OpenTelemetry se carga ANTES de la aplicacion (--import),
# asi instrumenta http, express, fetch/undici, pg y pino (trazas, metricas
# HTTP, propagacion W3C traceparent y trace_id en los registros JSON).
# Configuracion por variables OTEL_* en el chart (aroma-gitops).
EXPOSE 9464
CMD ["node", "--import", "@opentelemetry/auto-instrumentations-node/register", "src/index.js"]
