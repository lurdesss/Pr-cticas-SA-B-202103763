import pg from 'pg';

export const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 5 });

const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

export async function esperarBaseDeDatos(intentos = 15) {
  for (let intento = 1; intento <= intentos; intento += 1) {
    try {
      await pool.query('SELECT 1');
      return;
    } catch (error) {
      console.warn(`[pedidos] PostgreSQL no responde (intento ${intento}/${intentos}): ${error.message}`);
      await dormir(2000);
    }
  }
  throw new Error('PostgreSQL no respondio.');
}

const ESQUEMA = `
CREATE TABLE IF NOT EXISTS pedidos (
  id          SERIAL PRIMARY KEY,
  usuario_id  TEXT NOT NULL,
  usuario_nombre TEXT NOT NULL DEFAULT '',
  estado      TEXT NOT NULL DEFAULT 'recibido',
  notas       TEXT NOT NULL DEFAULT '',
  total       NUMERIC(10,2) NOT NULL DEFAULT 0,
  creado_en   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT ck_estado CHECK (estado IN ('recibido','preparando','listo','entregado','cancelado'))
);

CREATE TABLE IF NOT EXISTS pedido_items (
  id              SERIAL PRIMARY KEY,
  pedido_id       INTEGER NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  producto_id     TEXT NOT NULL,
  nombre_producto TEXT NOT NULL,
  precio_unitario NUMERIC(10,2) NOT NULL CHECK (precio_unitario >= 0),
  cantidad        INTEGER NOT NULL CHECK (cantidad > 0)
);

CREATE INDEX IF NOT EXISTS idx_pedidos_usuario ON pedidos(usuario_id);
CREATE INDEX IF NOT EXISTS idx_items_pedido ON pedido_items(pedido_id);
`;

export async function inicializarEsquema() {
  await pool.query(ESQUEMA);
}
