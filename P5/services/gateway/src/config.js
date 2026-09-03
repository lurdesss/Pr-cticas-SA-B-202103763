// Toda la configuracion entra por variables de entorno: las inyecta el
// ConfigMap del subchart "gateway". Ni una URL esta escrita en la logica.
//
// Nota de alcance (Practica 5): este gateway es el "simulador de API
// Gateway" que pide el enunciado. A diferencia del gateway de la
// Practica 4, aqui NO se verifica sesion ni permisos: la rubrica de esta
// practica evalua Helm, configuracion, persistencia, mensajeria, redes y
// resiliencia, no autenticacion. Añadir de vuelta auth-service y
// authz-service es posible (el codigo de P4 sigue existiendo) pero se
// dejo fuera para no duplicar alcance que esta practica no califica.

const numero = (valor, porDefecto) =>
  valor === undefined || valor === '' ? porDefecto : Number(valor);

export const config = {
  puerto: numero(process.env.PUERTO, 8000),

  servicios: {
    catalogo: process.env.CATALOGO_SERVICE_URL ?? 'http://catalogo:4001',
    inventario: process.env.INVENTARIO_SERVICE_URL ?? 'http://inventario:4002',
    pedidos: process.env.PEDIDOS_SERVICE_URL ?? 'http://pedidos:4003',
    resenas: process.env.RESENAS_SERVICE_URL ?? 'http://resenas:4004',
  },

  proxyTimeoutMs: numero(process.env.PROXY_TIMEOUT_MS, 15000),
};
