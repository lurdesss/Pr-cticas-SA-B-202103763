import { sinSesion, autenticacionNoDisponible, sesionIlegible } from './errores.js';

// El gateway NO abre el JWT. Le pregunta al servicio de autenticacion de la
// Practica 2, que es el unico que conoce el secreto y la ventana de gracia.
// Esta capa traduce la respuesta de ese servicio al formato que usa el
// gateway: si manana cambia el contrato de /auth/yo, solo cambia aqui.

function primerValor(objeto, rutas) {
  for (const ruta of rutas) {
    const valor = ruta
      .split('.')
      .reduce((actual, clave) => (actual === null || actual === undefined ? actual : actual[clave]), objeto);
    if (valor !== undefined && valor !== null && valor !== '') return valor;
  }
  return undefined;
}

export function normalizarSesion(cuerpo) {
  return {
    id: primerValor(cuerpo, ['id', 'usuario_id', 'usuarioId', 'sub', 'usuario.id', 'usuario.usuario_id']),
    rol: primerValor(cuerpo, ['rol', 'role', 'usuario.rol', 'usuario.role']),
    nombre: primerValor(cuerpo, ['nombre', 'name', 'usuario.nombre']) ?? '',
    correo: primerValor(cuerpo, ['correo', 'email', 'usuario.correo']) ?? '',
  };
}

function cookiesDe(respuesta) {
  if (typeof respuesta.headers.getSetCookie === 'function') return respuesta.headers.getSetCookie();
  const unica = respuesta.headers.get('set-cookie');
  return unica ? [unica] : [];
}

export function crearVerificadorDeSesion({ authUrl, timeoutMs }) {
  return async function verificarSesion(peticion, respuesta, siguiente) {
    if (!peticion.headers.cookie) return siguiente(sinSesion());

    let respuestaAuth;
    try {
      respuestaAuth = await fetch(`${authUrl}/auth/yo`, {
        headers: { cookie: peticion.headers.cookie },
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch {
      return siguiente(autenticacionNoDisponible());
    }

    if (respuestaAuth.status === 401 || respuestaAuth.status === 403) return siguiente(sinSesion());
    if (!respuestaAuth.ok) return siguiente(autenticacionNoDisponible());

    // Si el token entro en la ventana de gracia, el servicio de P2 devuelve
    // una cookie nueva. Hay que reenviarla al navegador o la renovacion
    // automatica se perderia en el camino.
    const cookies = cookiesDe(respuestaAuth);
    if (cookies.length > 0) respuesta.setHeader('Set-Cookie', cookies);
    const renovado = respuestaAuth.headers.get('x-token-renovado');
    if (renovado) respuesta.setHeader('X-Token-Renovado', renovado);

    let cuerpo;
    try {
      cuerpo = await respuestaAuth.json();
    } catch {
      return siguiente(sesionIlegible());
    }

    const sesion = normalizarSesion(cuerpo);
    if (!sesion.id || !sesion.rol) return siguiente(sesionIlegible());

    peticion.usuario = { ...sesion, id: String(sesion.id), rol: String(sesion.rol).toLowerCase() };
    return siguiente();
  };
}
