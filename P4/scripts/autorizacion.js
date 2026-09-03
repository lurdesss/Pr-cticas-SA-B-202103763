import { sinPermiso, autorizacionNoDisponible } from './errores.js';

const dormir = (ms) => new Promise((resolver) => setTimeout(resolver, ms));

// La ruta del microservicio de autorizacion es configurable: si en tu
// Practica 2 se llama distinto, cambiala con AUTHZ_VERIFICAR_RUTA sin tocar
// codigo.
const RUTA_VERIFICAR = process.env.AUTHZ_VERIFICAR_RUTA ?? '/autorizacion/verificar';

// Traduce un fallo de red al motivo concreto, en vez de dejar un mensaje
// generico que obliga a adivinar.
function describirFallo(error) {
  if (error?.name === 'TimeoutError' || error?.name === 'AbortError') {
    return 'TIMEOUT (el servicio existe pero tardo demasiado)';
  }
  const causa = error?.cause;
  const codigo = causa?.code ?? causa?.errors?.[0]?.code ?? error?.code;

  switch (codigo) {
    case 'ECONNREFUSED':
      return 'ECONNREFUSED (el contenedor existe pero nadie escucha en ese puerto)';
    case 'ENOTFOUND':
    case 'EAI_AGAIN':
      return `${codigo} (ese nombre de host no existe en la red de Docker: el contenedor esta caido o se llama distinto)`;
    case 'ECONNRESET':
      return 'ECONNRESET (el servicio corto la conexion)';
    default:
      return codigo ?? error?.message ?? 'desconocido';
  }
}

export function crearClienteAutorizacion({ url, maxReintentos, backoffInicialMs, backoffFactor, timeoutMs }) {
  const destino = `${url}${RUTA_VERIFICAR}`;

  // Comprobacion de arranque: una sola llamada al levantar, cuyo unico
  // objetivo es que el problema aparezca en el log al iniciar y no la
  // primera vez que alguien pulsa un boton.
  (async () => {
    try {
      const respuesta = await fetch(destino, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ rol: 'admin', permiso: 'catalogo:usar' }),
        signal: AbortSignal.timeout(5000),
      });
      const cuerpo = await respuesta.text();
      if (respuesta.ok) {
        console.log(`[gateway] autorizacion alcanzable en ${destino} -> ${respuesta.status} ${cuerpo}`);
      } else {
        console.error(
          `[gateway] AVISO: ${destino} respondio ${respuesta.status}. ` +
            'Si es 404, la ruta del microservicio se llama distinto: ajusta AUTHZ_VERIFICAR_RUTA. ' +
            `Cuerpo: ${cuerpo.slice(0, 200)}`,
        );
      }
    } catch (error) {
      console.error(
        `[gateway] AVISO: no se alcanza ${destino} -> ${describirFallo(error)}. ` +
          'Revisa "docker compose logs authz-service".',
      );
    }
  })();

  async function consultarUnaVez(rol, permiso, intento) {
    try {
      const respuesta = await fetch(destino, {
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
        const cuerpo = await respuesta.text();
        console.warn(
          `[gateway] autorizacion respondio ${respuesta.status} para rol=${rol} permiso=${permiso}. ` +
            `${respuesta.status === 404 ? `La ruta ${RUTA_VERIFICAR} no existe en el microservicio. ` : ''}` +
            `${respuesta.status === 422 ? 'El cuerpo {rol, permiso} no coincide con lo que espera. ' : ''}` +
            `Cuerpo: ${cuerpo.slice(0, 200)}`,
        );
        return false; // 4xx: reintentar no lo arregla
      }

      const cuerpo = await respuesta.json();
      return Boolean(cuerpo.permitido ?? cuerpo.allowed ?? cuerpo.autorizado);
    } catch (error) {
      console.warn(
        `[gateway] autorizacion sin respuesta (intento ${intento}/${maxReintentos}) en ${destino}: ` +
          describirFallo(error),
      );
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
