-- Esquema de la base de datos de autenticación.
-- Ejecutar una sola vez en Neon, Supabase o PostgreSQL local.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS usuarios (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Datos sensibles cifrados con AES-256-GCM (requisito 6).
    -- Son TEXT porque el texto cifrado en base64 excede la longitud
    -- del dato original.
    nombre_cifrado  TEXT NOT NULL,
    correo_cifrado  TEXT NOT NULL,

    -- Índice ciego: HMAC-SHA256 del correo normalizado. Permite buscar
    -- y garantizar unicidad sin descifrar la tabla completa.
    correo_indice   VARCHAR(64) NOT NULL UNIQUE,

    -- Las contraseñas se hashean con bcrypt, no se cifran: deben ser
    -- irreversibles incluso para el propio sistema.
    password_hash   VARCHAR(255) NOT NULL,

    rol             VARCHAR(20) NOT NULL,

    CONSTRAINT ck_rol_valido CHECK (rol IN ('admin', 'cliente'))
);

CREATE INDEX IF NOT EXISTS idx_usuarios_correo_indice ON usuarios (correo_indice);
