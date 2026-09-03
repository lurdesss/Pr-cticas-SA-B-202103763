import { pool } from './db.js';

// Unico lugar del servicio que escribe SQL. Todas las consultas van
// parametrizadas: ninguna concatena texto que venga del cliente.

const aProducto = (fila) => ({
  id: String(fila.id),
  categoriaId: String(fila.categoria_id),
  nombre: fila.nombre,
  descripcion: fila.descripcion,
  precio: Number(fila.precio),
  disponible: fila.disponible,
  creadoEn: fila.creado_en.toISOString(),
});

const aCategoria = (fila) => ({
  id: String(fila.id),
  nombre: fila.nombre,
  descripcion: fila.descripcion,
});

export const repositorio = {
  async listarProductos({ soloDisponibles = false, categoriaId = null } = {}) {
    const { rows } = await pool.query(
      `SELECT * FROM productos
        WHERE ($1::boolean IS NOT TRUE OR disponible = TRUE)
          AND ($2::int IS NULL OR categoria_id = $2::int)
        ORDER BY categoria_id, nombre`,
      [soloDisponibles, categoriaId],
    );
    return rows.map(aProducto);
  },

  async productoPorId(id) {
    const { rows } = await pool.query('SELECT * FROM productos WHERE id = $1', [id]);
    return rows[0] ? aProducto(rows[0]) : null;
  },

  async listarCategorias() {
    const { rows } = await pool.query('SELECT * FROM categorias ORDER BY id');
    return rows.map(aCategoria);
  },

  async categoriaPorId(id) {
    const { rows } = await pool.query('SELECT * FROM categorias WHERE id = $1', [id]);
    return rows[0] ? aCategoria(rows[0]) : null;
  },

  async crearProducto({ nombre, descripcion = '', precio, categoriaId, disponible = true }) {
    const { rows } = await pool.query(
      `INSERT INTO productos (categoria_id, nombre, descripcion, precio, disponible)
       VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [categoriaId, nombre, descripcion, precio, disponible],
    );
    return aProducto(rows[0]);
  },

  async cambiarDisponibilidad(id, disponible) {
    const { rows } = await pool.query(
      'UPDATE productos SET disponible = $2 WHERE id = $1 RETURNING *',
      [id, disponible],
    );
    return rows[0] ? aProducto(rows[0]) : null;
  },
};
