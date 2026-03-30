-- ═══════════════════════════════════════════════════════════════════════════
-- TrazaBox: contraseñas por RUT (pgcrypto + RPC para la app Flutter)
-- Ejecutar en Supabase → SQL Editor (proyecto correcto).
--
-- Corrige: function gen_salt(unknown) does not exist
--   → extensión pgcrypto + casts explícitos ::text en gen_salt / crypt
-- ═══════════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- Tabla interna: solo la tocan las funciones SECURITY DEFINER
CREATE TABLE IF NOT EXISTS public.trazabox_credenciales (
  rut                   TEXT PRIMARY KEY,
  password_hash         TEXT NOT NULL,
  must_change_password  BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Sin acceso directo desde PostgREST (solo las RPC SECURITY DEFINER tocan la tabla)
ALTER TABLE public.trazabox_credenciales DISABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.trazabox_credenciales FROM PUBLIC;
REVOKE ALL ON public.trazabox_credenciales FROM anon;
REVOKE ALL ON public.trazabox_credenciales FROM authenticated;

-- Últimos 4 dígitos del cuerpo del RUT (misma lógica que la app)
CREATE OR REPLACE FUNCTION public.trazabox_rut_ultimos_4(p_rut TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  s     TEXT := replace(replace(trim(p_rut), '.', ''), ' ', '');
  dash  INT;
  body  TEXT;
BEGIN
  dash := position('-' IN s);
  IF dash <= 0 THEN
    RETURN NULL;
  END IF;
  body := regexp_replace(substring(s FROM 1 FOR dash - 1), '[^0-9]', '', 'g');
  IF body IS NULL OR body = '' THEN
    RETURN NULL;
  END IF;
  IF length(body) <= 4 THEN
    RETURN body;
  END IF;
  RETURN right(body, 4);
END;
$$;

-- Login: fila en trazabox_credenciales → crypt; sin fila → primer acceso con últimos 4
CREATE OR REPLACE FUNCTION public.trazabox_login(p_rut TEXT, p_password TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_rut   TEXT := trim(p_rut);
  v_hash  TEXT;
  v_must  BOOLEAN;
  v_last4 TEXT;
BEGIN
  SELECT c.password_hash, c.must_change_password
    INTO v_hash, v_must
  FROM public.trazabox_credenciales c
  WHERE c.rut = v_rut;

  IF v_hash IS NOT NULL THEN
    IF extensions.crypt(p_password::TEXT, v_hash) = v_hash THEN
      RETURN json_build_object(
        'success', TRUE,
        'must_change_password', COALESCE(v_must, FALSE),
        'message', ''
      );
    END IF;
    RETURN json_build_object(
      'success', FALSE,
      'must_change_password', FALSE,
      'message', 'Contraseña incorrecta'
    );
  END IF;

  v_last4 := public.trazabox_rut_ultimos_4(v_rut);
  IF v_last4 IS NOT NULL AND p_password = v_last4 THEN
    RETURN json_build_object(
      'success', TRUE,
      'must_change_password', TRUE,
      'message', ''
    );
  END IF;

  RETURN json_build_object(
    'success', FALSE,
    'must_change_password', FALSE,
    'message', 'Contraseña incorrecta'
  );
END;
$$;

-- Primer cambio o rotación: valida actual (hash o últimos 4) y guarda bcrypt
CREATE OR REPLACE FUNCTION public.trazabox_set_password_inicial(
  p_rut TEXT,
  p_password_actual TEXT,
  p_password_nuevo TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_rut    TEXT := trim(p_rut);
  v_hash   TEXT;
  v_last4  TEXT;
  v_nuevo  TEXT := trim(p_password_nuevo);
  v_salt   TEXT;
  v_crypt  TEXT;
BEGIN
  IF length(v_nuevo) < 8 THEN
    RETURN json_build_object(
      'success', FALSE,
      'message', 'La nueva contraseña debe tener al menos 8 caracteres'
    );
  END IF;

  v_salt := extensions.gen_salt('bf'::TEXT);
  v_crypt := extensions.crypt(v_nuevo::TEXT, v_salt);

  SELECT c.password_hash INTO v_hash
  FROM public.trazabox_credenciales c
  WHERE c.rut = v_rut;

  v_last4 := public.trazabox_rut_ultimos_4(v_rut);

  IF v_hash IS NOT NULL THEN
    IF extensions.crypt(p_password_actual::TEXT, v_hash) <> v_hash THEN
      RETURN json_build_object(
        'success', FALSE,
        'message', 'Contraseña actual incorrecta'
      );
    END IF;

    UPDATE public.trazabox_credenciales
    SET
      password_hash = v_crypt,
      must_change_password = FALSE,
      updated_at = NOW()
    WHERE rut = v_rut;

    RETURN json_build_object('success', TRUE, 'message', '');
  END IF;

  IF v_last4 IS NULL OR p_password_actual <> v_last4 THEN
    RETURN json_build_object(
      'success', FALSE,
      'message', 'Contraseña inicial incorrecta'
    );
  END IF;

  INSERT INTO public.trazabox_credenciales (rut, password_hash, must_change_password)
  VALUES (v_rut, v_crypt, FALSE)
  ON CONFLICT (rut) DO UPDATE SET
    password_hash = EXCLUDED.password_hash,
    must_change_password = FALSE,
    updated_at = NOW();

  RETURN json_build_object('success', TRUE, 'message', '');
END;
$$;

GRANT EXECUTE ON FUNCTION public.trazabox_rut_ultimos_4(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trazabox_login(TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trazabox_set_password_inicial(TEXT, TEXT, TEXT) TO anon, authenticated;
