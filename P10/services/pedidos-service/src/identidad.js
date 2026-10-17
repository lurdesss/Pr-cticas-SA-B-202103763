// Traduce las cabeceras de identidad a un objeto de dominio.
//
// Nota de alcance (Practica 5): el gateway de esta practica es un
// "simulador" sin verificacion de sesion (ver services/gateway). Por eso
// estas cabeceras viajan sin firmar: quien las manda es quien las llama
// (curl, Postman, el script de carga). Alcanza para probar el enrutado
// por rol; NO es un mecanismo de seguridad. La verificacion real vive en
// la Practica 4 (auth-service + authz-service) y puede reincorporarse sin
// tocar esta funcion.
export function identidadDe(peticion) {
  const decodificar = (valor) => {
    try {
      return valor ? decodeURIComponent(valor) : '';
    } catch {
      return '';
    }
  };

  return {
    id: peticion.headers['x-usuario-id'] || 'anonimo',
    rol: (peticion.headers['x-usuario-rol'] || 'cliente').toLowerCase(),
    nombre: decodificar(peticion.headers['x-usuario-nombre']) || 'Invitado',
  };
}

export const esAdmin = (identidad) => identidad.rol === 'admin';
