FROM node:20-alpine

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY src ./src

EXPOSE 8000

HEALTHCHECK --interval=10s --timeout=3s --retries=5 --start-period=10s \
  CMD node -e "fetch('http://127.0.0.1:8000/salud').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "src/index.js"]
