import { createProxyMiddleware } from 'http-proxy-middleware';

// Reescritura de ruta tolerante: funciona tanto si Express ya quito el
// prefijo del montaje como si no, porque en ambos casos produce la misma
// ruta final para el servicio destino.
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

    // Identidad ya verificada. Los microservicios de negocio confian en
    // estas cabeceras porque solo son alcanzables desde la red interna:
    // el unico puerto publicado hacia afuera es el del edge.
    onProxyReq: (peticionProxy, peticion) => {
      if (!peticion.usuario) return;
      peticionProxy.setHeader('X-Usuario-Id', peticion.usuario.id);
      peticionProxy.setHeader('X-Usuario-Rol', peticion.usuario.rol);
      peticionProxy.setHeader('X-Usuario-Nombre', encodeURIComponent(peticion.usuario.nombre));
      peticionProxy.setHeader('X-Usuario-Correo', encodeURIComponent(peticion.usuario.correo));
      if (peticion.permisoConcedido) peticionProxy.setHeader('X-Permiso', peticion.permisoConcedido);
    },

    onError: (error, peticion, respuesta) => {
      console.error(`[gateway] fallo al hablar con ${destino}${peticion.url}: ${error.message}`);
      if (respuesta.headersSent) return;
      respuesta.writeHead(503, { 'content-type': 'application/json' });
      respuesta.end(
        JSON.stringify({ detalle: 'El microservicio destino no respondio.', codigo: 'SERVICIO_NO_DISPONIBLE' }),
      );
    },
  });
}
