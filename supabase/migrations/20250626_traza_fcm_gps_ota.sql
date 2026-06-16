-- TrazaBox: tokens FCM, tabla GPS material y config OTA

ALTER TABLE supervisores_traza
  ADD COLUMN IF NOT EXISTS fcm_token text;

ALTER TABLE tecnicos_traza_zc
  ADD COLUMN IF NOT EXISTS fcm_token text;

CREATE TABLE IF NOT EXISTS public.tecnicos_ubicacion (
  id bigserial PRIMARY KEY,
  tecnico_id text NOT NULL UNIQUE,
  nombre text,
  telefono text,
  latitud double precision,
  longitud double precision,
  estado text DEFAULT 'disponible',
  ot_actual text,
  ultima_actualizacion timestamptz DEFAULT now(),
  en_linea boolean DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_tecnicos_ubicacion_en_linea
  ON public.tecnicos_ubicacion (en_linea)
  WHERE en_linea = true;

ALTER TABLE public.tecnicos_ubicacion ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tecnicos upsert propia ubicacion" ON public.tecnicos_ubicacion;
CREATE POLICY "Tecnicos upsert propia ubicacion"
  ON public.tecnicos_ubicacion FOR ALL
  USING (true)
  WITH CHECK (true);

-- OTA TRAZABOX
INSERT INTO configuracion_app (clave, valor, descripcion) VALUES
  ('traza_version', '2.0.0', 'Versión semántica APK TrazaBox'),
  ('traza_build', '6', 'Build APK TrazaBox'),
  ('traza_apk_url', '', 'URL APK; vacío = GitHub Releases'),
  ('traza_actualizacion_forzada', 'false', 'true = bloquea hasta instalar'),
  ('traza_notas_actualizacion', '', 'Notas de release')
ON CONFLICT (clave) DO NOTHING;

DROP POLICY IF EXISTS "Anon puede leer config traza" ON configuracion_app;
CREATE POLICY "Anon puede leer config traza"
  ON configuracion_app FOR SELECT
  USING (clave LIKE 'traza_%');
