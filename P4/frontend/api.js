// Cliente unico del API Gateway.
// Todo el frontend sale por /api, servido en el mismo origen por el edge
// (nginx). Al ser el mismo origen, el navegador manda la cookie de sesion
// sin CORS y sin que ningun script pueda leerla: sigue siendo HttpOnly.

export const BASE = '/api';

// Nombres de los campos que espera el servicio de autenticacion de la
// Practica 2. Si en tu P2 se llaman distinto, cambialos aqui: es el unico
// punto del frontend que los menciona.
export const CAMPOS = {
  registro: { nombre: 'nombre', correo: 'correo', password: 'password', rol: 'rol' },
  login: { correo: 'correo', password: 'password' },
  roles: { admin: 'admin', cliente: 'cliente' },
};

const oyentes = [];
export const alRegistrar = (oyente) => oyentes.push(oyente);
const anotar = (entrada) => oyentes.forEach((oyente) => oyente(entrada));

export class ErrorApi extends Error {
  constructor(estado, detalle, codigo) {
    super(detalle);
    this.estado = estado;
    this.detalle = detalle;
    this.codigo = codigo;
  }
}

async function pedir(ruta, opciones = {}) {
  const inicio = Date.now();
  const metodo = opciones.method ?? 'GET';

  let respuesta;
  try {
    respuesta = await fetch(`${BASE}${ruta}`, {
      credentials: 'same-origin',
      headers: opciones.cuerpo ? { 'content-type': 'application/json' } : {},
      body: opciones.cuerpo ? JSON.stringify(opciones.cuerpo) : undefined,
      ...opciones,
    });
  } catch {
    anotar({ metodo, ruta, estado: 0, ms: Date.now() - inicio, nota: 'sin red' });
    throw new ErrorApi(0, 'No se pudo contactar al servidor.', 'SIN_RED');
  }

  const renovado = respuesta.headers.get('X-Token-Renovado') === 'true';
  anotar({ metodo, ruta, estado: respuesta.status, ms: Date.now() - inicio, renovado });

  if (respuesta.status === 204) return null;

  const texto = await respuesta.text();
  let cuerpo = null;
  try {
    cuerpo = texto ? JSON.parse(texto) : null;
  } catch {
    cuerpo = { detalle: texto };
  }

  if (!respuesta.ok) {
    const detalle = cuerpo?.detalle ?? cuerpo?.detail ?? cuerpo?.mensaje ?? 'La peticion fallo.';
    throw new ErrorApi(respuesta.status, detalle, cuerpo?.codigo);
  }

  return cuerpo;
}

export const api = {
  // ----------------------------------------------------------- sesion
  registro: (datos) => pedir('/auth/registro', { method: 'POST', cuerpo: datos }),
  login: (datos) => pedir('/auth/login', { method: 'POST', cuerpo: datos }),
  logout: () => pedir('/auth/logout', { method: 'POST' }),
  yo: () => pedir('/auth/yo'),

  // ---------------------------------------------------------- sistema
  salud: () => pedir('/salud'),
  diagnostico: () => pedir('/diagnostico'),

  // -------------------------------------------------- GraphQL: menu
  async catalogo(consulta, variables = {}) {
    const cuerpo = await pedir('/catalogo/graphql', {
      method: 'POST',
      cuerpo: { query: consulta, variables },
    });
    if (cuerpo.errors?.length) throw new ErrorApi(400, cuerpo.errors[0].message, 'GRAPHQL');
    return cuerpo.data;
  },

  // --------------------------------------------- GraphQL: inventario
  async inventario(consulta, variables = {}) {
    const cuerpo = await pedir('/inventario/graphql', {
      method: 'POST',
      cuerpo: { query: consulta, variables },
    });
    if (cuerpo.errors?.length) throw new ErrorApi(400, cuerpo.errors[0].message, 'GRAPHQL');
    return cuerpo.data;
  },

  // ------------------------------------------------------ REST: pedidos
  crearPedido: (items, notas) => pedir('/pedidos', { method: 'POST', cuerpo: { items, notas } }),
  listarPedidos: () => pedir('/pedidos'),
  cambiarEstadoPedido: (id, estado) =>
    pedir(`/pedidos/${id}/estado`, { method: 'PATCH', cuerpo: { estado } }),

  // ------------------------------------------------------ REST: resenas
  listarResenas: (productoId) =>
    pedir(`/resenas${productoId ? `?producto_id=${encodeURIComponent(productoId)}` : ''}`),
  promediosResenas: () => pedir('/resenas/promedios'),
  crearResena: (datos) => pedir('/resenas', { method: 'POST', cuerpo: datos }),
  eliminarResena: (id) => pedir(`/resenas/${id}`, { method: 'DELETE' }),
};

// -------------------------------------------------------------- utiles

export const escapar = (valor) =>
  String(valor ?? '').replace(/[&<>"']/g, (caracter) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[caracter],
  );

export const quetzales = (monto) => `Q ${Number(monto).toFixed(2)}`;
