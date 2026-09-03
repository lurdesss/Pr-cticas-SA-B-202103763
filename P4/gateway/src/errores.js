// Un unico tipo de error con estado HTTP. La capa de transporte es la
// unica que sabe traducirlo a una respuesta.

export class ErrorHttp extends Error {
  constructor(estado, detalle, codigo) {
    super(detalle);
    this.estado = estado;
    this.detalle = detalle;
    this.codigo = codigo;
  }
}

export const sinSesion = () =>
  new ErrorHttp(401, 'No hay una sesion activa.', 'SIN_SESION');

export const sinPermiso = (permiso) =>
  new ErrorHttp(403, `La sesion no tiene el permiso ${permiso}.`, 'SIN_PERMISO');

export const autorizacionNoDisponible = (intentos) =>
  new ErrorHttp(
    503,
    `El servicio de autorizacion no respondio tras ${intentos} intentos.`,
    'AUTORIZACION_NO_DISPONIBLE',
  );

export const autenticacionNoDisponible = () =>
  new ErrorHttp(503, 'El servicio de autenticacion no respondio.', 'AUTENTICACION_NO_DISPONIBLE');

export const sesionIlegible = () =>
  new ErrorHttp(
    502,
    'El servicio de autenticacion respondio con una forma inesperada. Revisa normalizarSesion en gateway/src/sesion.js.',
    'SESION_ILEGIBLE',
  );

export function manejadorDeErrores(error, _req, respuesta, _next) {
  if (error instanceof ErrorHttp) {
    return respuesta.status(error.estado).json({ detalle: error.detalle, codigo: error.codigo });
  }
  console.error('[gateway] error no controlado:', error);
  return respuesta.status(500).json({ detalle: 'Error interno del gateway.', codigo: 'ERROR_INTERNO' });
}
