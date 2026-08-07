/**
 * Cliente HTTP compartido por las páginas.
 *
 * Todas las peticiones usan `credentials: "include"` para que el navegador
 * envíe la cookie de sesión. El token nunca se lee ni se guarda desde
 * JavaScript: es HTTP-only, así que `document.cookie` no lo ve.
 */

const API_BASE = "http://127.0.0.1:8000";

/** Tiempos del token, expuestos por el backend para dibujar el ciclo de vida. */
const CONFIG_TOKEN = { ttl: 180, gracia: 60 };

/**
 * Realiza una petición a la API y normaliza la respuesta.
 * Devuelve siempre { ok, status, datos, renovado } en lugar de lanzar,
 * para que cada pantalla decida cómo mostrar el error.
 */
async function peticion(ruta, opciones = {}) {
  const respuesta = await fetch(`${API_BASE}${ruta}`, {
    ...opciones,
    credentials: "include",
    headers: { "Content-Type": "application/json", ...(opciones.headers || {}) },
  });

  let datos = null;
  try {
    datos = await respuesta.json();
  } catch {
    datos = null;
  }

  return {
    ok: respuesta.ok,
    status: respuesta.status,
    datos,
    renovado: respuesta.headers.get("X-Token-Renovado") === "true",
  };
}

const api = {
  registro: (cuerpo) =>
    peticion("/auth/registro", { method: "POST", body: JSON.stringify(cuerpo) }),
  login: (cuerpo) =>
    peticion("/auth/login", { method: "POST", body: JSON.stringify(cuerpo) }),
  yo: () => peticion("/auth/yo"),
  logout: () => peticion("/auth/logout", { method: "POST" }),
  ruta1: () => peticion("/recursos/ruta1"),
  ruta2: () => peticion("/recursos/ruta2"),
};

/** Traduce un código de estado a un mensaje que el usuario entienda. */
function describirError(status, datos) {
  const detalle = datos?.detalle;
  if (detalle) return detalle;

  switch (status) {
    case 401: return "La sesión no es válida o ya expiró.";
    case 403: return "Tu rol no tiene acceso a este recurso.";
    case 422: return "Revisa los datos: alguno no tiene el formato esperado.";
    case 503: return "El servicio de autorización no responde. Intenta de nuevo.";
    default: return `Error inesperado (${status}).`;
  }
}
