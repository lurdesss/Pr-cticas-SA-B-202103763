import { pool } from './db.js';

const aItem = (fila) => ({
  productoId: fila.producto_id,
  nombreProducto: fila.nombre_producto,
  precioUnitario: Number(fila.precio_unitario),
  cantidad: fila.cantidad,
  subtotal: Number(fila.precio_unitario) * fila.cantidad,
});

const aPedido = (fila, items = []) => ({
  id: fila.id,
  usuarioId: fila.usuario_id,
  usuarioNombre: fila.usuario_nombre,
  estado: fila.estado,
  notas: fila.notas,
  total: Number(fila.total),
  creadoEn: fila.creado_en.toISOString(),
  items,
});

export const repositorio = {
  async crear({ usuarioId, usuarioNombre, notas, items }) {
    const cliente = await pool.connect();
    try {
      await cliente.query('BEGIN');

      const total = items.reduce((suma, item) => suma + item.precioUnitario * item.cantidad, 0);
      const { rows } = await cliente.query(
        `INSERT INTO pedidos (usuario_id, usuario_nombre, notas, total)
         VALUES ($1, $2, $3, $4) RETURNING *`,
        [usuarioId, usuarioNombre, notas, total.toFixed(2)],
      );
      const pedido = rows[0];

      for (const item of items) {
        await cliente.query(
          `INSERT INTO pedido_items (pedido_id, producto_id, nombre_producto, precio_unitario, cantidad)
           VALUES ($1, $2, $3, $4, $5)`,
          [pedido.id, item.productoId, item.nombreProducto, item.precioUnitario, item.cantidad],
        );
      }

      await cliente.query('COMMIT');
      return aPedido(pedido, items.map((item) => ({ ...item, subtotal: item.precioUnitario * item.cantidad })));
    } catch (error) {
      await cliente.query('ROLLBACK');
      throw error;
    } finally {
      cliente.release();
    }
  },

  async listar({ usuarioId = null, estado = null } = {}) {
    const { rows } = await pool.query(
      `SELECT * FROM pedidos
        WHERE ($1::text IS NULL OR usuario_id = $1::text)
          AND ($2::text IS NULL OR estado = $2::text)
        ORDER BY creado_en DESC
        LIMIT 100`,
      [usuarioId, estado],
    );
    if (rows.length === 0) return [];

    const { rows: items } = await pool.query(
      'SELECT * FROM pedido_items WHERE pedido_id = ANY($1::int[])',
      [rows.map((fila) => fila.id)],
    );

    return rows.map((fila) =>
      aPedido(fila, items.filter((item) => item.pedido_id === fila.id).map(aItem)),
    );
  },

  async porId(id) {
    const { rows } = await pool.query('SELECT * FROM pedidos WHERE id = $1', [id]);
    if (!rows[0]) return null;
    const { rows: items } = await pool.query('SELECT * FROM pedido_items WHERE pedido_id = $1', [id]);
    return aPedido(rows[0], items.map(aItem));
  },

  async cambiarEstado(id, estado) {
    const { rows } = await pool.query(
      'UPDATE pedidos SET estado = $2 WHERE id = $1 RETURNING *',
      [id, estado],
    );
    return rows[0] ? this.porId(id) : null;
  },
};
