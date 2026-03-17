-- ══════════════════════════════════════════════════════════
-- Agrega columna orden_de_trabajo a la tabla access_id
-- Ejecutar en Supabase SQL Editor
-- ══════════════════════════════════════════════════════════

-- 1. Agregar columna (si no existe)
ALTER TABLE access_id
  ADD COLUMN IF NOT EXISTS orden_de_trabajo TEXT;

-- 2. Índice para búsquedas rápidas por OT
CREATE INDEX IF NOT EXISTS idx_access_id_ot
  ON access_id (orden_de_trabajo);

-- 3. Verificar estructura actual
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'access_id'
ORDER BY ordinal_position;
