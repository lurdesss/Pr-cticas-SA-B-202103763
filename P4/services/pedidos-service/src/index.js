import express from 'express';

import { esperarBaseDeDatos, inicializarEsquema } from './db.js';
import { repositorio } from './repositorio.js';
import { obtenerProducto, ErrorCatalogoNoDisponible } from './catalogo.js';
import { identidadDe, esAdmin } from './identidad.js';

const puerto = Number(process.env.PUERTO ?? 4003);
const ESTADOS = ['recibido', 'preparando', 'listo', 'entregado', 'cancelado'];

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '128kb' }));

app.get('/salud', (_peticion, respuesta) =>
  respuesta.json({ servicio: 'pedidos-service', estado: 'arriba', api: 'REST', lenguaje: 'Node.js' }),
);

// ------------------------------------------------------- crear pedido
app.post('/pedidos', async (peticion, respuesta) => {
  const identidad = identidadDe(peticion);
  const { items, notas = '' } = peticion.body ?? {};

  if (!Array.isArray(items) || items.length === 0) {
    return respuesta.status(422).json({ detalle: 'Envia al menos un item.', codigo: 'PEDIDO_VACIO' });
  }
  if (items.length > 20) {
    return respuesta.status(422).json({ detalle: 'Un pedido admite hasta 20 items.', codigo: 'PEDIDO_MUY_LARGO' });
  }

  const resueltos = [];
  try {
    for (const item of items) {
      const cantidad = Number(item.cantidad ?? 1);
      if (!Number.isInteger(cantidad) || cantidad < 1 || cantidad > 50) {
        return respuesta
          .status(422)
          .json({ detalle: 'La cantidad debe ser un entero entre 1 y 50.', codigo: 'CANTIDAD_INVALIDA' });
      }

      const producto = await obtenerProducto(item.productoId);
      if (!producto) {
        return respuesta
          .status(422)
          .json({ detalle: `El producto ${item.productoId} no existe en el catalogo.`, codigo: 'PRODUCTO_INEXISTENTE' });
      }
      if (!producto.disponible) {
        return respuesta
          .status(409)
          .json({ detalle: `${producto.nombre} esta agotado.`, codigo: 'PRODUCTO_AGOTADO' });
      }

      resueltos.push({
        productoId: String(producto.id),
        nombreProducto: producto.nombre,
        precioUnitario: Number(producto.precio),
        cantidad,
      });
    }
  } catch (error) {
    if (error instanceof ErrorCatalogoNoDisponible) {
      // El catalogo es la fuente del precio. Sin el no se cobra a ciegas.
      return respuesta.status(503).json({
        detalle: 'El catalogo no respondio; intenta de nuevo en unos segundos.',
        codigo: 'CATALOGO_NO_DISPONIBLE',
      });
    }
    throw error;
  }

  const pedido = await repositorio.crear({
    usuarioId: identidad.id,
    usuarioNombre: identidad.nombre,
    notas: String(notas).slice(0, 200),
    items: resueltos,
  });

  return respuesta.status(201).json(pedido);
});

// ------------------------------------------------------ listar pedidos
app.get('/pedidos', async (peticion, respuesta) => {
  const identidad = identidadDe(peticion);
  const estado = peticion.query.estado ?? null;

  // Un Cliente solo ve lo suyo; un Admin ve la comanda completa.
  const pedidos = await repositorio.listar({
    usuarioId: esAdmin(identidad) ? null : identidad.id,
    estado: estado && ESTADOS.includes(estado) ? estado : null,
  });

  return respuesta.json({ total: pedidos.length, pedidos });
});

// --------------------------------------------------------- ver pedido
app.get('/pedidos/:id', async (peticion, respuesta) => {
  const identidad = identidadDe(peticion);
  const pedido = await repositorio.porId(Number(peticion.params.id));

  if (!pedido) return respuesta.status(404).json({ detalle: 'Ese pedido no existe.', codigo: 'NO_ENCONTRADO' });
  if (!esAdmin(identidad) && pedido.usuarioId !== identidad.id) {
    return respuesta.status(403).json({ detalle: 'Ese pedido es de otra persona.', codigo: 'PEDIDO_AJENO' });
  }

  return respuesta.json(pedido);
});

// ------------------------------------------------------ cambiar estado
app.patch('/pedidos/:id/estado', async (peticion, respuesta) => {
  const { estado } = peticion.body ?? {};
  if (!ESTADOS.includes(estado)) {
    return respuesta
      .status(422)
      .json({ detalle: `Estado invalido. Usa uno de: ${ESTADOS.join(', ')}.`, codigo: 'ESTADO_INVALIDO' });
  }

  const pedido = await repositorio.cambiarEstado(Number(peticion.params.id), estado);
  if (!pedido) return respuesta.status(404).json({ detalle: 'Ese pedido no existe.', codigo: 'NO_ENCONTRADO' });

  return respuesta.json(pedido);
});

app.use((error, _peticion, respuesta, _siguiente) => {
  console.error('[pedidos] error no controlado:', error);
  respuesta.status(500).json({ detalle: 'Error interno del servicio de pedidos.', codigo: 'ERROR_INTERNO' });
});

await esperarBaseDeDatos();
await inicializarEsquema();

app.listen(puerto, () => console.log(`[pedidos] REST escuchando en el puerto ${puerto}`));
