-- ═══════════════════════════════════════════════════════════════
-- MIGRACIÓN: Soporte multi-tecnología en producción
-- Ejecutar en Supabase → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- 1. Columna tecnología en tabla produccion
--    Valores: 'RED_NEUTRA', 'HFC', 'FTTH'
ALTER TABLE produccion
  ADD COLUMN IF NOT EXISTS tecnologia TEXT DEFAULT 'RED_NEUTRA';

-- 2. Puntos HFC calculados por AppScript
--    Solo se llena para órdenes HFC completadas
ALTER TABLE produccion
  ADD COLUMN IF NOT EXISTS puntos_hfc NUMERIC DEFAULT 0;

-- 3. Categoría HFC (1 PLAY, 2 PLAY, SSTT, etc.) para trazabilidad
ALTER TABLE produccion
  ADD COLUMN IF NOT EXISTS categoria_hfc TEXT DEFAULT '';

-- 4. Tipo de contrato en tabla de técnicos
--    'nuevo'  = todo se cuenta junto en RGU (contrato unificado)
--    'antiguo' = tecnologías separadas (RED_NEUTRA RGU | HFC PTS | FTTH RGU)
ALTER TABLE tecnicos_traza_zc
  ADD COLUMN IF NOT EXISTS tipo_contrato TEXT DEFAULT 'nuevo';

-- ═══════════════════════════════════════════════════════════════
-- ÍNDICE para consultas por tecnología
-- ═══════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_produccion_tecnologia
  ON produccion (rut_tecnico, tecnologia, fecha_trabajo);

-- ═══════════════════════════════════════════════════════════════
-- VERIFICAR: Ejemplo para un técnico
-- ═══════════════════════════════════════════════════════════════

-- SELECT tecnologia, COUNT(*) as ordenes, SUM(rgu_total) as rgu, SUM(puntos_hfc) as pts
-- FROM produccion
-- WHERE rut_tecnico = 'XXXXXXXX-X'
-- GROUP BY tecnologia;
