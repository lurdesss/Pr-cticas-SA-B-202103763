FROM node:20-alpine AS dependencias
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

FROM node:20-alpine AS runtime
WORKDIR /app
RUN addgroup -S aroma && adduser -S aroma -G aroma
COPY --from=dependencias /app/node_modules ./node_modules
COPY package.json script.js ./
USER aroma
CMD ["node", "script.js"]
