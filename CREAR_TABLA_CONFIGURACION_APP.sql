-- ═══════════════════════════════════════════════════════════════════════════
-- TABLA configuracion_app
-- Almacena credenciales y parámetros de APIs externas (Nyquist, etc.)
-- Ejecutar UNA SOLA VEZ en Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Crear tabla
CREATE TABLE IF NOT EXISTS configuracion_app (
  id          BIGSERIAL PRIMARY KEY,
  clave       TEXT NOT NULL UNIQUE,
  valor       TEXT NOT NULL,
  descripcion TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Índice
CREATE INDEX IF NOT EXISTS idx_configuracion_app_clave ON configuracion_app(clave);

-- 3. Trigger updated_at
CREATE OR REPLACE FUNCTION update_configuracion_app_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_configuracion_app ON configuracion_app;
CREATE TRIGGER trg_update_configuracion_app
  BEFORE UPDATE ON configuracion_app
  FOR EACH ROW EXECUTE FUNCTION update_configuracion_app_updated_at();

-- 4. Row Level Security
ALTER TABLE configuracion_app ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Autenticados pueden leer configuracion" ON configuracion_app;
CREATE POLICY "Autenticados pueden leer configuracion"
  ON configuracion_app FOR SELECT
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Solo service_role puede modificar configuracion" ON configuracion_app;
CREATE POLICY "Solo service_role puede modificar configuracion"
  ON configuracion_app FOR ALL
  USING (auth.role() = 'service_role');

-- 5. Insertar credenciales Nyquist
INSERT INTO configuracion_app (clave, valor, descripcion) VALUES
  ('nyquist_base_url',  'https://nyquisttraza.sbip.cl',              'URL base de la API Nyquist'),
  ('nyquist_user',      '0npVpRUG7MegtpmfdDuJ3A',                    'Usuario Basic Auth Nyquist'),
  ('nyquist_password',  'Ddw3u241Y0MN_x7ezZixKIJtk1ZRHpG6Zz2tCYrhXVg', 'Password Basic Auth Nyquist'),
  ('nyquist_vno_id',    '02',                                         'VNO ID de Creaciones Tecnológicas (prefijo del access_id)')
ON CONFLICT (clave) DO UPDATE
  SET valor       = EXCLUDED.valor,
      descripcion = EXCLUDED.descripcion,
      updated_at  = NOW();

-- 6. Verificar (debe mostrar 4 filas)
SELECT clave, descripcion, LEFT(valor, 15) || '...' AS valor_parcial
FROM configuracion_app
WHERE clave LIKE 'nyquist%'
ORDER BY clave;
