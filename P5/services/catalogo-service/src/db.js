import pg from 'pg';

export const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  max: 5,
  idleTimeoutMillis: 30000,
});

const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

export async function esperarBaseDeDatos(intentos = 15) {
  for (let intento = 1; intento <= intentos; intento += 1) {
    try {
      await pool.query('SELECT 1');
      return;
    } catch (error) {
      console.warn(`[catalogo] PostgreSQL no responde (intento ${intento}/${intentos}): ${error.message}`);
      await dormir(2000);
    }
  }
  throw new Error('PostgreSQL no respondio.');
}

const ESQUEMA = `
CREATE TABLE IF NOT EXISTS categorias (
  id           SERIAL PRIMARY KEY,
  nombre       TEXT NOT NULL UNIQUE,
  descripcion  TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS productos (
  id            SERIAL PRIMARY KEY,
  categoria_id  INTEGER NOT NULL REFERENCES categorias(id) ON DELETE RESTRICT,
  nombre        TEXT NOT NULL,
  descripcion   TEXT NOT NULL DEFAULT '',
  precio        NUMERIC(10,2) NOT NULL CHECK (precio >= 0),
  disponible    BOOLEAN NOT NULL DEFAULT TRUE,
  creado_en     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_productos_categoria ON productos(categoria_id);
`;

const SEMILLA = [
  ['Cafe caliente', 'Extracciones en barra, servidas al momento.', [
    ['Espresso', 'Doble ristretto de finca Acatenango.', 12.0],
    ['Cortado', 'Espresso con leche vaporizada en proporcion 1:1.', 16.0],
    ['Latte de cardamomo', 'Leche entera infusionada con cardamomo verde.', 24.0],
    ['Filtrado V60', 'Metodo manual, grano de la semana.', 22.0],
  ]],
  ['Cafe frio', 'Preparados en frio, servidos sobre hielo.', [
    ['Cold brew', 'Dieciseis horas de extraccion en frio.', 20.0],
    ['Tonica de cafe', 'Cold brew con agua tonica y naranja.', 26.0],
  ]],
  ['Reposteria', 'Horneado cada manana en casa.', [
    ['Concha de vainilla', 'Masa dulce con costra de vainilla.', 10.0],
    ['Banana bread', 'Con nuez y un toque de canela.', 18.0],
    ['Galleta de chocolate', 'Chocolate al 70 por ciento.', 12.0],
  ]],
];

export async function inicializarEsquema() {
  await pool.query(ESQUEMA);

  const { rows } = await pool.query('SELECT COUNT(*)::int AS total FROM categorias');
  if (rows[0].total > 0) return;

  const cliente = await pool.connect();
  try {
    await cliente.query('BEGIN');
    for (const [nombre, descripcion, productos] of SEMILLA) {
      const categoria = await cliente.query(
        'INSERT INTO categorias (nombre, descripcion) VALUES ($1, $2) RETURNING id',
        [nombre, descripcion],
      );
      for (const [nombreProducto, descripcionProducto, precio] of productos) {
        await cliente.query(
          'INSERT INTO productos (categoria_id, nombre, descripcion, precio) VALUES ($1, $2, $3, $4)',
          [categoria.rows[0].id, nombreProducto, descripcionProducto, precio],
        );
      }
    }
    await cliente.query('COMMIT');
    console.log('[catalogo] datos de ejemplo cargados.');
  } catch (error) {
    await cliente.query('ROLLBACK');
    throw error;
  } finally {
    cliente.release();
  }
}
