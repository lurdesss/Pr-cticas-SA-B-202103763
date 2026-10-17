const SONDAS = [
  { nombre: 'catalogo', clave: 'catalogo', ruta: '/salud' },
  { nombre: 'inventario', clave: 'inventario', ruta: '/salud' },
  { nombre: 'pedidos', clave: 'pedidos', ruta: '/salud' },
  { nombre: 'resenas', clave: 'resenas', ruta: '/salud' },
];

export async function estadoDelSistema(servicios, timeoutMs = 2000) {
  const resultados = await Promise.all(
    SONDAS.map(async (sonda) => {
      const inicio = Date.now();
      try {
        const respuesta = await fetch(`${servicios[sonda.clave]}${sonda.ruta}`, { signal: AbortSignal.timeout(timeoutMs) });
        return { servicio: sonda.nombre, estado: respuesta.ok ? 'arriba' : 'degradado', codigo: respuesta.status, ms: Date.now() - inicio };
      } catch (error) {
        return { servicio: sonda.nombre, estado: 'caido', codigo: null, ms: Date.now() - inicio, detalle: error.message };
      }
    }),
  );
  return { servicio: 'gateway', estado: resultados.every((r) => r.estado === 'arriba') ? 'arriba' : 'degradado', dependencias: resultados };
}
