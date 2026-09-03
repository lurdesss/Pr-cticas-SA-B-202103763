// Mapa declarativo de rutas: prefijo publico -> servicio destino.
// Agregar un microservicio nuevo es agregar una entrada aqui; nada mas
// en el gateway necesita tocarse (principio abierto/cerrado, igual que
// en la Practica 4).
export const rutas = [
  { prefijo: '/api/catalogo', destino: 'catalogo', destinoBase: '' },
  { prefijo: '/api/inventario', destino: 'inventario', destinoBase: '' },
  { prefijo: '/api/pedidos', destino: 'pedidos', destinoBase: '' },
  { prefijo: '/api/resenas', destino: 'resenas', destinoBase: '' },
];
