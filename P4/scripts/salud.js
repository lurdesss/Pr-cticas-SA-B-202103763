// Sonda agregada: pregunta a cada servicio si esta vivo. Ahora incluye el
// motivo concreto del fallo, no solo la etiqueta "caido".

const SONDAS = [
  { nombre: 'auth-service', clave: 'auth', ruta: '/openapi.json' },
  { nombre: 'authz-service', clave: 'authz', ruta: '/openapi.json' },
  { nombre: 'catalogo-service', clave: 'catalogo', ruta: '/salud' },
  { nombre: 'inventario-service', clave: 'inventario', ruta: '/salud' },
  { nombre: 'pedidos-service', clave: 'pedidos', ruta: '/salud' },
  { nombre: 'resenas-service', clave: 'resenas', ruta: '/salud' },
];

function describirFallo(error) {
  if (error?.name === 'TimeoutError' || error?.name === 'AbortError') return 'timeout';
  const causa = error?.cause;
  return causa?.code ?? causa?.errors?.[0]?.code ?? error?.code ?? error?.message ?? 'desconocido';
}

export async function estadoDelSistema(servicios, timeoutMs = 2000) {
  const resultados = await Promise.all(
    SONDAS.map(async (sonda) => {
      const inicio = Date.now();
      const url = `${servicios[sonda.clave]}${sonda.ruta}`;
      try {
        const respuesta = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
        return {
          servicio: sonda.nombre,
          url,
          estado: respuesta.ok ? 'arriba' : 'degradado',
          codigo: respuesta.status,
          ms: Date.now() - inicio,
          detalle: respuesta.ok ? '' : `respondio ${respuesta.status}`,
        };
      } catch (error) {
        return {
          servicio: sonda.nombre,
          url,
          estado: 'caido',
          codigo: null,
          ms: Date.now() - inicio,
          detalle: describirFallo(error),
        };
      }
    }),
  );

  return {
    servicio: 'gateway',
    estado: resultados.every((r) => r.estado === 'arriba') ? 'arriba' : 'degradado',
    dependencias: resultados,
  };
}
