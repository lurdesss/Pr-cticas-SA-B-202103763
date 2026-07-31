-- Esquema de la base de datos de solicitudes operativas.
-- Ejecutar una sola vez en Neon, Supabase o PostgreSQL local.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS solicitudes_operativas (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    titulo           VARCHAR(120) NOT NULL,
    area_solicitante VARCHAR(80)  NOT NULL,
    prioridad        SMALLINT     NOT NULL,
    costo_estimado   NUMERIC(12, 2) NOT NULL,
    estado           VARCHAR(20)  NOT NULL,

    -- Las reglas también viven en la base de datos: si otro cliente
    -- escribiera directamente, los datos siguen siendo válidos.
    CONSTRAINT ck_prioridad_rango   CHECK (prioridad BETWEEN 1 AND 5),
    CONSTRAINT ck_costo_no_negativo CHECK (costo_estimado >= 0),
    CONSTRAINT ck_estado_valido     CHECK (estado IN ('registrada', 'en_proceso', 'finalizada'))
);

CREATE INDEX IF NOT EXISTS idx_solicitudes_estado    ON solicitudes_operativas (estado);
CREATE INDEX IF NOT EXISTS idx_solicitudes_prioridad ON solicitudes_operativas (prioridad);
