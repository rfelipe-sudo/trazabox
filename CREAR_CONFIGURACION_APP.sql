-- ══════════════════════════════════════════════════════════════════════
-- TABLA configuracion_app
-- Almacena configuración sensible (API keys, URLs) fuera del código
-- ══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS configuracion_app (
  id          SERIAL PRIMARY KEY,
  clave       TEXT UNIQUE NOT NULL,
  valor       TEXT NOT NULL,
  descripcion TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Solo usuarios autenticados pueden leer (nunca escribir desde el app)
ALTER TABLE configuracion_app ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Autenticados leen config" ON configuracion_app
  FOR SELECT USING (auth.role() = 'authenticated');

-- ══════════════════════════════════════════════════════════════════════
-- CREDENCIALES API NYQUIST (estado vecino / asistente CTO)
-- ══════════════════════════════════════════════════════════════════════
INSERT INTO configuracion_app (clave, valor, descripcion) VALUES
  ('nyquist_user',     '0npVpRUG7MegtpmfdDuJ3A',                    'Usuario Basic Auth API Nyquist CTO'),
  ('nyquist_password', 'Ddw3u241Y0MN_x7ezZixKIJtk1ZRHpG6Zz2tCYrhXVg', 'Password Basic Auth API Nyquist CTO'),
  ('nyquist_base_url', 'https://nyquisttraza.sbip.cl',               'URL base API Nyquist'),
  ('nyquist_vno_id',   '02',                                         'VNO ID prefijo para access_id')
ON CONFLICT (clave) DO UPDATE
  SET valor = EXCLUDED.valor,
      updated_at = NOW();
