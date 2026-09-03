// Toda la configuracion entra por variables de entorno: ni una URL ni un
// tiempo esta escrito dentro de la logica.

const numero = (valor, porDefecto) =>
  valor === undefined || valor === '' ? porDefecto : Number(valor);

export const config = {
  puerto: numero(process.env.PUERTO, 8000),

  servicios: {
    auth: process.env.AUTH_SERVICE_URL ?? 'http://auth-service:8000',
    authz: process.env.AUTHZ_SERVICE_URL ?? 'http://authz-service:8001',
    catalogo: process.env.CATALOGO_SERVICE_URL ?? 'http://catalogo-service:4001',
    inventario: process.env.INVENTARIO_SERVICE_URL ?? 'http://inventario-service:4002',
    pedidos: process.env.PEDIDOS_SERVICE_URL ?? 'http://pedidos-service:4003',
    resenas: process.env.RESENAS_SERVICE_URL ?? 'http://resenas-service:4004',
  },

  autorizacion: {
    maxReintentos: numero(process.env.AUTHZ_MAX_REINTENTOS, 4),
    backoffInicialMs: numero(process.env.AUTHZ_BACKOFF_INICIAL_MS, 200),
    backoffFactor: numero(process.env.AUTHZ_BACKOFF_FACTOR, 2),
    timeoutMs: numero(process.env.AUTHZ_TIMEOUT_MS, 2000),
  },

  sesionTimeoutMs: numero(process.env.SESION_TIMEOUT_MS, 4000),
  proxyTimeoutMs: numero(process.env.PROXY_TIMEOUT_MS, 15000),
};
