import { createProxyMiddleware } from 'http-proxy-middleware';

function reescribir(prefijo, destinoBase) {
  return (ruta) => {
    const sinPrefijo = ruta.startsWith(prefijo) ? ruta.slice(prefijo.length) : ruta;
    const final = `${destinoBase}${sinPrefijo}`;
    return final === '' ? '/' : final;
  };
}

export function crearProxy({ destino, prefijo, destinoBase = '', timeoutMs }) {
  return createProxyMiddleware({
    target: destino,
    changeOrigin: true,
    xfwd: true,
    proxyTimeout: timeoutMs,
    timeout: timeoutMs,
    pathRewrite: reescribir(prefijo, destinoBase),
    logLevel: 'warn',
    onError: (error, peticion, respuesta) => {
      console.error(`[gateway] fallo al hablar con ${destino}${peticion.url}: ${error.message}`);
      if (respuesta.headersSent) return;
      respuesta.writeHead(503, { 'content-type': 'application/json' });
      respuesta.end(JSON.stringify({ detalle: 'El microservicio destino no respondio.', codigo: 'SERVICIO_NO_DISPONIBLE' }));
    },
  });
}
