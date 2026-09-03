// El gateway inyecta la identidad ya verificada en cabeceras. El servicio
// no vuelve a abrir el JWT ni conoce el secreto: no es asunto suyo.
export function contextoDesdePeticion(peticion) {
  const decodificar = (valor) => {
    try {
      return valor ? decodeURIComponent(valor) : '';
    } catch {
      return '';
    }
  };

  return {
    usuarioId: peticion.headers['x-usuario-id'] ?? null,
    rol: (peticion.headers['x-usuario-rol'] ?? '').toLowerCase(),
    nombre: decodificar(peticion.headers['x-usuario-nombre']),
  };
}
