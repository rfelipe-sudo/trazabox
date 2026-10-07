-- ════════════════════════════════════════════════════════════════════
-- CARGA MANUAL — equipos_seriados_traza (histórico agosto hacia atrás)
-- ════════════════════════════════════════════════════════════════════
-- La tabla guarda: orden de trabajo, RUT del técnico, tipo de equipo
-- (ONT / DECO / EXTENSOR / GATEWAY / MTA / OTRO) y número de serie.
--
-- Desde hoy en adelante la llena sola el Apps Script
-- (APPSCRIPT_EQUIPOS_SERIADOS_TRAZA.js). Este archivo es la plantilla
-- para cargar a mano el histórico anterior.
--
-- CÓMO USAR:
-- 1. Copia el bloque INSERT y agrega una fila por equipo.
-- 2. Pégalo en Supabase → SQL Editor → Run.
-- 3. El ON CONFLICT hace que repetir una carga NO duplique registros
--    (la llave es orden_trabajo + serie), así que es seguro reintentar.
--
-- Si tienes los datos en Excel/CSV con columnas
-- (orden_trabajo, rut_tecnico, tipo_equipo, serie, fecha_trabajo):
-- también puedes usar Supabase → Table Editor → equipos_seriados_traza
-- → Insert → Import data from CSV (agregando la columna fuente='manual').

INSERT INTO equipos_seriados_traza
  (orden_trabajo, rut_tecnico, tipo_equipo, serie, fecha_trabajo, fuente)
VALUES
  -- ('1-3XXXXXXX', '12345678-9', 'ONT',      'SERIE_AQUI', '2026-08-01', 'manual'),
  -- ('1-3XXXXXXX', '12345678-9', 'DECO',     'SERIE_AQUI', '2026-08-01', 'manual'),
  -- ('1-3XXXXXXX', '12345678-9', 'EXTENSOR', 'SERIE_AQUI', '2026-08-01', 'manual'),
  ('EJEMPLO_BORRAR', '00000000-0', 'OTRO', 'EJEMPLO_BORRAR', '2026-08-01', 'manual')
ON CONFLICT (orden_trabajo, serie) DO NOTHING;

-- Borrar la fila de ejemplo:
DELETE FROM equipos_seriados_traza WHERE orden_trabajo = 'EJEMPLO_BORRAR';

-- Verificar lo cargado:
-- SELECT fecha_trabajo, count(*) FROM equipos_seriados_traza
-- GROUP BY 1 ORDER BY 1 DESC;
