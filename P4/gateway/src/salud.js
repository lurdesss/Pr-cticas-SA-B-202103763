// Sonda agregada: pregunta a cada servicio si esta vivo. Sirve para la
// demostracion y para depurar sin abrir siete terminales.

const SONDAS = [
  { nombre: 'auth-service', clave: 'auth', ruta: '/openapi.json' },
  { nombre: 'authz-service', clave: 'authz', ruta: '/openapi.json' },
  { nombre: 'catalogo-service', clave: 'catalogo', ruta: '/salud' },
  { nombre: 'inventario-service', clave: 'inventario', ruta: '/salud' },
  { nombre: 'pedidos-service', clave: 'pedidos', ruta: '/salud' },
  { nombre: 'resenas-service', clave: 'resenas', ruta: '/salud' },
];

export async function estadoDelSistema(servicios, timeoutMs = 2000) {
  const resultados = await Promise.all(
    SONDAS.map(async (sonda) => {
      const inicio = Date.now();
      try {
        const respuesta = await fetch(`${servicios[sonda.clave]}${sonda.ruta}`, {
          signal: AbortSignal.timeout(timeoutMs),
        });
        return {
          servicio: sonda.nombre,
          estado: respuesta.ok ? 'arriba' : 'degradado',
          codigo: respuesta.status,
          ms: Date.now() - inicio,
        };
      } catch {
        return { servicio: sonda.nombre, estado: 'caido', codigo: null, ms: Date.now() - inicio };
      }
    }),
  );

  return {
    servicio: 'gateway',
    estado: resultados.every((r) => r.estado === 'arriba') ? 'arriba' : 'degradado',
    dependencias: resultados,
  };
}
