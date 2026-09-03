// Traduce las cabeceras que inyecta el gateway a un objeto de dominio.
export function identidadDe(peticion) {
  const decodificar = (valor) => {
    try {
      return valor ? decodeURIComponent(valor) : '';
    } catch {
      return '';
    }
  };

  return {
    id: peticion.headers['x-usuario-id'] ?? '',
    rol: (peticion.headers['x-usuario-rol'] ?? '').toLowerCase(),
    nombre: decodificar(peticion.headers['x-usuario-nombre']),
  };
}

export const esAdmin = (identidad) => identidad.rol === 'admin';
