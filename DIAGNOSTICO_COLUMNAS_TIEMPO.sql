-- ═══════════════════════════════════════════════════════════════════
-- DIAGNÓSTICO: COLUMNAS DE TIEMPO EN LA TABLA PRODUCCION
-- ═══════════════════════════════════════════════════════════════════

-- 1. Ver la estructura de la tabla produccion (columnas disponibles)
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'produccion'
  AND column_name IN ('hora_inicio', 'hora_fin', 'duracion_min', 'hora_atencion', 'hora_cierre', 'duracion', 'tiempo_atencion')
ORDER BY column_name;

-- 2. Ver todas las columnas de la tabla produccion
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'produccion'
ORDER BY ordinal_position;

-- 3. Ver ejemplos de registros con valores en columnas de tiempo (si existen)
SELECT 
    rut_tecnico,
    tecnico,
    fecha_trabajo,
    orden_trabajo,
    estado
    -- ⚠️ Agrega aquí las columnas de tiempo que veas en la consulta 2
    -- Ejemplo:
    -- , hora_inicio
    -- , hora_fin
    -- , duracion_min
FROM produccion
WHERE fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%'
LIMIT 5;

-- 4. Contar cuántos registros tienen hora_inicio no nula (si la columna existe)
-- ⚠️ Descomenta solo si la columna existe:
-- SELECT 
--     COUNT(*) AS total_registros,
--     COUNT(hora_inicio) AS con_hora_inicio,
--     COUNT(hora_fin) AS con_hora_fin,
--     COUNT(duracion_min) AS con_duracion_min
-- FROM produccion
-- WHERE fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%';

-- 5. Ver si existe la vista v_tiempos_tecnicos (para horas extras)
SELECT EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_name = 'v_tiempos_tecnicos'
) AS vista_existe;

-- 6. Si la vista existe, ver su estructura
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'v_tiempos_tecnicos'
ORDER BY ordinal_position;

