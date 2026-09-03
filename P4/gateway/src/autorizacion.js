import { sinPermiso, autorizacionNoDisponible } from './errores.js';

const dormir = (ms) => new Promise((resolver) => setTimeout(resolver, ms));

// Cliente del microservicio de autorizacion, con la misma regla de la
// Practica 2: "sin permiso" es una respuesta definitiva; "sin respuesta" es
// un fallo transitorio que se reintenta con espera creciente.
export function crearClienteAutorizacion({ url, maxReintentos, backoffInicialMs, backoffFactor, timeoutMs }) {
  async function consultarUnaVez(rol, permiso, intento) {
    try {
      const respuesta = await fetch(`${url}/autorizacion/verificar`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ rol, permiso }),
        signal: AbortSignal.timeout(timeoutMs),
      });

      if (respuesta.status >= 500) {
        console.warn(`[gateway] autorizacion respondio ${respuesta.status} (intento ${intento}/${maxReintentos}).`);
        return null; // transitorio
      }
      if (!respuesta.ok) {
        console.warn(`[gateway] autorizacion respondio ${respuesta.status}: reintentar no lo arregla.`);
        return false; // 4xx: peticion mal formada, veredicto negativo
      }

      const cuerpo = await respuesta.json();
      return Boolean(cuerpo.permitido);
    } catch {
      console.warn(`[gateway] autorizacion sin respuesta (intento ${intento}/${maxReintentos}).`);
      return null;
    }
  }

  return async function verificarPermiso(rol, permiso) {
    let espera = backoffInicialMs;

    for (let intento = 1; intento <= maxReintentos; intento += 1) {
      const veredicto = await consultarUnaVez(rol, permiso, intento);
      if (veredicto !== null) return veredicto;

      if (intento < maxReintentos) {
        console.warn(`[gateway] reintentando en ${(espera / 1000).toFixed(2)} s.`);
        await dormir(espera);
        espera *= backoffFactor;
      }
    }

    console.error(`[gateway] autorizacion agoto ${maxReintentos} intentos para rol=${rol} permiso=${permiso}.`);
    throw autorizacionNoDisponible(maxReintentos);
  };
}

// Fabrica de guardas. Agregar una ruta protegida nueva no obliga a tocar
// este archivo: basta declarar el permiso que exige.
export function exigirPermiso(verificarPermiso, resolverPermiso) {
  return async function guarda(peticion, _respuesta, siguiente) {
    const permiso = typeof resolverPermiso === 'function' ? resolverPermiso(peticion) : resolverPermiso;
    try {
      const permitido = await verificarPermiso(peticion.usuario.rol, permiso);
      if (!permitido) return siguiente(sinPermiso(permiso));
      peticion.permisoConcedido = permiso;
      return siguiente();
    } catch (error) {
      return siguiente(error);
    }
  };
}
