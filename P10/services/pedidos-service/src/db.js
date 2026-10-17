import { registro } from './registro.js';
import pg from 'pg';

export const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 5 });

const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

export async function esperarBaseDeDatos(intentos = 15) {
  for (let intento = 1; intento <= intentos; intento += 1) {
    try {
      await pool.query('SELECT 1');
      return;
    } catch (error) {
      registro.warn({ intento, intentos, error: error.message }, 'PostgreSQL no responde');
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

-- ---------------------------------------------------------------------
-- Tablas de los dos cronjobs de la Practica 5. Viven en pedidos_db para
-- no introducir una sexta base de datos; ningun otro servicio las toca.

-- Cronjob 1 (cada 2 min) inserta aqui la marca de ejecucion.
CREATE TABLE IF NOT EXISTS ejecuciones_cron (
  id          SERIAL PRIMARY KEY,
  carne       TEXT NOT NULL,
  ejecutado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Cronjob 2 (cada 10 min) publica el resumen en RabbitMQ; el consumidor
-- (pedidos-worker) lo guarda aqui al procesarlo.
CREATE TABLE IF NOT EXISTS resumenes_cron (
  id             SERIAL PRIMARY KEY,
  hora           TIMESTAMPTZ NOT NULL,
  total_ejecuciones INTEGER NOT NULL,
  generado_en    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  procesado_en   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- El consumidor de eventos de pedidos (pedidos-worker) anota aqui que
-- proceso el evento. Es la evidencia de que el flujo asincrono corrio.
CREATE TABLE IF NOT EXISTS notificaciones_pedidos (
  id          SERIAL PRIMARY KEY,
  pedido_id   INTEGER NOT NULL,
  mensaje     TEXT NOT NULL,
  procesado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Practica 6: el gateway publica un evento por cada peticion que reenvia
-- (fire-and-forget, sin esperar respuesta); pedidos-worker lo consume de
-- forma independiente y lo guarda aqui. Es la comunicacion asincrona
-- gateway <-> microservicio que exige esta practica, separada del
-- proxy sincrono normal que atiende la peticion HTTP original.
CREATE TABLE IF NOT EXISTS auditoria_gateway (
  id            SERIAL PRIMARY KEY,
  metodo        TEXT NOT NULL,
  ruta          TEXT NOT NULL,
  ip_origen     TEXT NOT NULL DEFAULT '',
  publicado_en  TIMESTAMPTZ NOT NULL,
  procesado_en  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
`;

export async function inicializarEsquema() {
  await pool.query(ESQUEMA);
}
