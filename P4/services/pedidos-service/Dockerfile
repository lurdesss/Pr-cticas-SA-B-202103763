FROM node:20-alpine

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY src ./src

EXPOSE 4003

HEALTHCHECK --interval=10s --timeout=3s --retries=6 --start-period=15s \
  CMD node -e "fetch('http://127.0.0.1:4003/salud').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "src/index.js"]
