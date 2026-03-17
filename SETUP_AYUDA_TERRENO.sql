-- ============================================================
-- SETUP AYUDA EN TERRENO — TrazaBox
-- Ejecutar en Supabase SQL Editor
-- ============================================================

-- 1. Tabla principal de solicitudes de ayuda
CREATE TABLE IF NOT EXISTS ayuda_terreno (
  id            BIGSERIAL PRIMARY KEY,
  ticket_id     TEXT UNIQUE DEFAULT gen_random_uuid()::text,
  rut_tecnico   TEXT NOT NULL,
  nombre_tecnico TEXT,
  lat_tecnico   DOUBLE PRECISION NOT NULL,
  lng_tecnico   DOUBLE PRECISION NOT NULL,
  tipo          TEXT NOT NULL,
  -- 'zona_roja' | 'cruce_peligroso' | 'ducto' | 'fusion' | 'altura'
  rut_supervisor TEXT,
  nombre_supervisor TEXT,
  lat_supervisor DOUBLE PRECISION,
  lng_supervisor DOUBLE PRECISION,
  distancia_km  DOUBLE PRECISION,
  estado        TEXT DEFAULT 'pendiente',
  -- 'pendiente' | 'aceptada' | 'rechazada' | 'aceptada_con_tiempo'
  tiempo_extra_minutos INTEGER,
  respuesta_mensaje TEXT,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Trigger para actualizar updated_at automáticamente
CREATE OR REPLACE FUNCTION update_ayuda_terreno_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_ayuda_terreno_updated_at ON ayuda_terreno;
CREATE TRIGGER trg_ayuda_terreno_updated_at
  BEFORE UPDATE ON ayuda_terreno
  FOR EACH ROW EXECUTE FUNCTION update_ayuda_terreno_updated_at();

-- 3. Columnas de ubicación para supervisores (para cálculo de proximidad)
ALTER TABLE supervisores_traza
  ADD COLUMN IF NOT EXISTS lat_ultima DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS lng_ultima DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS ultima_ubicacion_at TIMESTAMPTZ;

-- 4. RLS
ALTER TABLE ayuda_terreno ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ayuda_select" ON ayuda_terreno;
DROP POLICY IF EXISTS "ayuda_insert" ON ayuda_terreno;
DROP POLICY IF EXISTS "ayuda_update" ON ayuda_terreno;

CREATE POLICY "ayuda_select" ON ayuda_terreno FOR SELECT USING (true);
CREATE POLICY "ayuda_insert" ON ayuda_terreno FOR INSERT WITH CHECK (true);
CREATE POLICY "ayuda_update" ON ayuda_terreno FOR UPDATE USING (true);

-- 5. Habilitar Realtime en la tabla
-- Ejecutar SOLO si no está ya en la publicación
ALTER PUBLICATION supabase_realtime ADD TABLE ayuda_terreno;

-- 6. Índices para consultas frecuentes
CREATE INDEX IF NOT EXISTS idx_ayuda_rut_tecnico  ON ayuda_terreno (rut_tecnico);
CREATE INDEX IF NOT EXISTS idx_ayuda_rut_supervisor ON ayuda_terreno (rut_supervisor);
CREATE INDEX IF NOT EXISTS idx_ayuda_estado        ON ayuda_terreno (estado);
CREATE INDEX IF NOT EXISTS idx_ayuda_created       ON ayuda_terreno (created_at DESC);

-- Verificación final
SELECT 'Tabla ayuda_terreno creada exitosamente' AS resultado;
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'ayuda_terreno' ORDER BY ordinal_position;
