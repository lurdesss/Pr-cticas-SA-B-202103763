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

CMD ["node", "src/worker.js"]
