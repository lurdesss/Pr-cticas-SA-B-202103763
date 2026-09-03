// Mapa declarativo de rutas. El gateway no sabe que hace cada
// microservicio: solo sabe a donde reenviar y que permiso exigir.
//
//   prefijo        -> ruta publica que ve el navegador
//   destino        -> clave dentro de config.servicios
//   destinoBase    -> prefijo que espera el servicio destino
//   publico        -> true = no exige sesion (solo /api/auth)
//   permisos       -> permiso requerido por metodo HTTP
//   permisoPorDefecto -> para los metodos no listados

export const rutas = [
  {
    prefijo: '/api/auth',
    destino: 'auth',
    destinoBase: '/auth',
    publico: true,
  },
  {
    prefijo: '/api/catalogo',
    destino: 'catalogo',
    destinoBase: '',
    permisos: {},
    permisoPorDefecto: 'catalogo:usar',
  },
  {
    prefijo: '/api/inventario',
    destino: 'inventario',
    destinoBase: '',
    permisos: {},
    permisoPorDefecto: 'inventario:gestionar',
  },
  {
    prefijo: '/api/pedidos',
    destino: 'pedidos',
    destinoBase: '/pedidos',
    permisos: {
      GET: 'pedidos:leer',
      POST: 'pedidos:crear',
      PATCH: 'pedidos:gestionar',
      PUT: 'pedidos:gestionar',
      DELETE: 'pedidos:gestionar',
    },
    permisoPorDefecto: 'pedidos:leer',
  },
  {
    prefijo: '/api/resenas',
    destino: 'resenas',
    destinoBase: '/resenas',
    permisos: {
      GET: 'resenas:leer',
      POST: 'resenas:escribir',
      DELETE: 'resenas:moderar',
    },
    permisoPorDefecto: 'resenas:leer',
  },
];

export function resolverPermiso(ruta) {
  return (peticion) => ruta.permisos?.[peticion.method] ?? ruta.permisoPorDefecto;
}

export function permisosDeclarados() {
  const todos = rutas.flatMap((ruta) => [
    ...Object.values(ruta.permisos ?? {}),
    ...(ruta.permisoPorDefecto ? [ruta.permisoPorDefecto] : []),
  ]);
  return [...new Set(todos)].sort();
}
