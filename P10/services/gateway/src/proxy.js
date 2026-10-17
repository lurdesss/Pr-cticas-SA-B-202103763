import { createProxyMiddleware } from 'http-proxy-middleware';
import { registro } from './registro.js';

function reescribir(prefijo, destinoBase) {
  return (ruta) => {
    const sinPrefijo = ruta.startsWith(prefijo) ? ruta.slice(prefijo.length) : ruta;
    const final = `${destinoBase}${sinPrefijo}`;
    return final === '' ? '/' : final;
  };
}

// Exportada para poder probarla de forma aislada (ver test/proxy.test.js):
// es la unica pieza de logica no trivial de este archivo, el resto es
// configuracion de la libreria de proxy.
export { reescribir };

export function crearProxy({ destino, prefijo, destinoBase = '', timeoutMs }) {
  return createProxyMiddleware({
    target: destino,
    changeOrigin: true,
    xfwd: true,
    proxyTimeout: timeoutMs,
    timeout: timeoutMs,
    pathRewrite: reescribir(prefijo, destinoBase),
    // 'silent': la libreria escribiria su propia linea de texto plano
    // ("[HPM] Error occurred...") y romperia el formato JSON de los
    // registros; el error ya se registra en JSON en onError.
    logLevel: 'silent',
    onError: (error, peticion, respuesta) => {
      registro.error({ destino, ruta: peticion.url, error: error.message }, 'el microservicio destino no respondio');
      if (respuesta.headersSent) return;
      respuesta.writeHead(503, { 'content-type': 'application/json' });
      respuesta.end(JSON.stringify({ detalle: 'El microservicio destino no respondio.', codigo: 'SERVICIO_NO_DISPONIBLE' }));
    },
  });
}
