-- ═══════════════════════════════════════════════════════════════════
-- DIAGNÓSTICO: ¿Por qué siguen habiendo timestamps?
-- ═══════════════════════════════════════════════════════════════════

-- 1. Ver cuántos registros TODAVÍA tienen timestamps en Enero
SELECT 
    'Enero con timestamps' as tipo,
    COUNT(*) as cantidad
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND rut_tecnico LIKE '%-%-T%';

-- 2. Ver cuántos registros tienen RUT correcto en Enero
SELECT 
    'Enero con RUT correcto' as tipo,
    COUNT(*) as cantidad
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND rut_tecnico NOT LIKE '%-%-T%'
  AND rut_tecnico IS NOT NULL
  AND rut_tecnico != '';

-- 3. Ver ejemplos de registros con timestamp
SELECT 
    rut_tecnico,
    tecnico,
    fecha_trabajo,
    orden_trabajo,
    estado
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND rut_tecnico LIKE '%-%-T%'
LIMIT 10;

-- 4. Verificar si esos técnicos EXISTEN en tecnicos_traza_zc
SELECT DISTINCT
    p.tecnico as nombre_en_produccion,
    t.rut as rut_en_tecnicos_traza,
    t.nombre_completo as nombre_en_tecnicos_traza
FROM produccion p
LEFT JOIN tecnicos_traza_zc t ON LOWER(TRIM(p.tecnico)) = LOWER(TRIM(t.nombre_completo))
WHERE (p.fecha_trabajo LIKE '%/01/26%' OR p.fecha_trabajo LIKE '%/01/2026%')
  AND p.rut_tecnico LIKE '%-%-T%'
LIMIT 10;

-- 5. Ver si hay diferencias en los nombres que impiden el match
SELECT DISTINCT
    p.tecnico,
    LENGTH(p.tecnico) as longitud,
    COUNT(*) as registros_con_timestamp
FROM produccion p
WHERE (p.fecha_trabajo LIKE '%/01/26%' OR p.fecha_trabajo LIKE '%/01/2026%')
  AND p.rut_tecnico LIKE '%-%-T%'
GROUP BY p.tecnico, LENGTH(p.tecnico)
ORDER BY registros_con_timestamp DESC;

