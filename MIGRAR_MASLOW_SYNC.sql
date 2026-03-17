-- ═══════════════════════════════════════════════════════════════
-- MIGRACIÓN: Soporte sincronización desde Maslow
-- Ejecutar en Supabase → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- Columnas adicionales para trazar el origen Maslow
ALTER TABLE tecnicos_traza_zc
  ADD COLUMN IF NOT EXISTS maslow_id         INTEGER,
  ADD COLUMN IF NOT EXISTS email             TEXT,
  ADD COLUMN IF NOT EXISTS ultima_sync_maslow TIMESTAMPTZ;

-- Asegurar que activo exista (puede que ya esté)
ALTER TABLE tecnicos_traza_zc
  ADD COLUMN IF NOT EXISTS activo BOOLEAN DEFAULT TRUE;

-- tipo_contrato ya existe desde migración anterior, solo asegurar default
-- 'nuevo'   = todo en RGU agrupado
-- 'antiguo' = RED NEUTRA RGU | HFC PTS | FTTH RGU por separado
ALTER TABLE tecnicos_traza_zc
  ALTER COLUMN tipo_contrato SET DEFAULT 'nuevo';

-- Índice para búsqueda rápida por maslow_id
CREATE INDEX IF NOT EXISTS idx_tecnicos_maslow_id
  ON tecnicos_traza_zc (maslow_id);

-- ═══════════════════════════════════════════════════════════════
-- VERIFICAR estructura resultante
-- ═══════════════════════════════════════════════════════════════

-- SELECT rut, nombre_completo, activo, tipo_contrato, maslow_id, ultima_sync_maslow
-- FROM tecnicos_traza_zc
-- ORDER BY nombre_completo;
