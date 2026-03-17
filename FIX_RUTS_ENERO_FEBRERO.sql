-- ═══════════════════════════════════════════════════════════════════
-- CORREGIR RUTs MAL CARGADOS EN ENERO Y FEBRERO
-- ═══════════════════════════════════════════════════════════════════
-- Problema: El rut_tecnico está vacío o tiene timestamps en lugar del RUT
-- Solución: Actualizar basándose en el nombre del técnico desde tecnicos_traza_zc
-- ═══════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════
-- PASO 1: Ver cuántos registros se corregirán
-- ══════════════════════════════════════════════════════════════════

SELECT 
    'ENERO' as mes,
    COUNT(*) as registros_con_problema
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND (rut_tecnico IS NULL OR rut_tecnico = '' OR rut_tecnico LIKE '%-%-T%');

SELECT 
    'FEBRERO' as mes,
    COUNT(*) as registros_con_problema
FROM produccion
WHERE (fecha_trabajo LIKE '%/02/26%' OR fecha_trabajo LIKE '%/02/2026%')
  AND (rut_tecnico IS NULL OR rut_tecnico = '' OR rut_tecnico LIKE '%-%-T%');

-- ══════════════════════════════════════════════════════════════════
-- PASO 2: Crear tabla temporal con el mapeo nombre → RUT
-- ══════════════════════════════════════════════════════════════════

CREATE TEMP TABLE temp_mapeo_tecnicos AS
SELECT DISTINCT 
    p.tecnico,
    t.rut as rut_correcto
FROM produccion p
LEFT JOIN tecnicos_traza_zc t 
    ON LOWER(TRIM(p.tecnico)) = LOWER(TRIM(t.nombre_completo))
WHERE p.tecnico IS NOT NULL 
  AND p.tecnico != ''
  AND t.rut IS NOT NULL;

-- Verificar el mapeo
SELECT * FROM temp_mapeo_tecnicos ORDER BY tecnico;

-- ══════════════════════════════════════════════════════════════════
-- PASO 3: ACTUALIZAR ENERO - RUTs vacíos o con timestamp
-- ══════════════════════════════════════════════════════════════════

UPDATE produccion p
SET rut_tecnico = tm.rut_correcto
FROM temp_mapeo_tecnicos tm
WHERE p.tecnico = tm.tecnico
  AND (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND (p.rut_tecnico IS NULL OR p.rut_tecnico = '' OR p.rut_tecnico LIKE '%-%-T%');

-- ══════════════════════════════════════════════════════════════════
-- PASO 4: ACTUALIZAR FEBRERO - RUTs vacíos o con timestamp
-- ══════════════════════════════════════════════════════════════════

UPDATE produccion p
SET rut_tecnico = tm.rut_correcto
FROM temp_mapeo_tecnicos tm
WHERE p.tecnico = tm.tecnico
  AND (fecha_trabajo LIKE '%/02/26%' OR fecha_trabajo LIKE '%/02/2026%')
  AND (p.rut_tecnico IS NULL OR p.rut_tecnico = '' OR p.rut_tecnico LIKE '%-%-T%');

-- ══════════════════════════════════════════════════════════════════
-- PASO 5: VERIFICAR QUE SE CORRIGIÓ
-- ══════════════════════════════════════════════════════════════════

-- Alberto Escalona en ENERO (debe mostrar ~95 órdenes con RUT correcto)
SELECT 
    rut_tecnico,
    COUNT(*) as ordenes,
    COUNT(*) FILTER (WHERE estado = 'Completado') as completadas,
    ROUND(SUM(rgu_total) FILTER (WHERE estado = 'Completado'), 2) as rgu_total
FROM produccion
WHERE tecnico = 'Alberto Escalona G'
  AND (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
GROUP BY rut_tecnico;

-- Alberto Escalona en FEBRERO (debe mostrar ~100 órdenes con RUT correcto)
SELECT 
    rut_tecnico,
    COUNT(*) as ordenes,
    COUNT(*) FILTER (WHERE estado = 'Completado') as completadas,
    ROUND(SUM(rgu_total) FILTER (WHERE estado = 'Completado'), 2) as rgu_total
FROM produccion
WHERE tecnico = 'Alberto Escalona G'
  AND (fecha_trabajo LIKE '%/02/26%' OR fecha_trabajo LIKE '%/02/2026%')
GROUP BY rut_tecnico;

-- ══════════════════════════════════════════════════════════════════
-- PASO 6: RESUMEN FINAL
-- ══════════════════════════════════════════════════════════════════

SELECT 
    'ENERO' as mes,
    COUNT(*) FILTER (WHERE rut_tecnico IS NOT NULL AND rut_tecnico != '' AND rut_tecnico NOT LIKE '%-%-T%') as corregidos,
    COUNT(*) FILTER (WHERE rut_tecnico IS NULL OR rut_tecnico = '' OR rut_tecnico LIKE '%-%-T%') as aun_con_problema,
    COUNT(*) as total
FROM produccion
WHERE fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%'

UNION ALL

SELECT 
    'FEBRERO' as mes,
    COUNT(*) FILTER (WHERE rut_tecnico IS NOT NULL AND rut_tecnico != '' AND rut_tecnico NOT LIKE '%-%-T%') as corregidos,
    COUNT(*) FILTER (WHERE rut_tecnico IS NULL OR rut_tecnico = '' OR rut_tecnico LIKE '%-%-T%') as aun_con_problema,
    COUNT(*) as total
FROM produccion
WHERE fecha_trabajo LIKE '%/02/26%' OR fecha_trabajo LIKE '%/02/2026%';

-- ══════════════════════════════════════════════════════════════════
-- NOTAS:
-- ══════════════════════════════════════════════════════════════════
-- 1. Este script corrige los RUTs basándose en el nombre del técnico
-- 2. Si un técnico NO está en tecnicos_traza_zc, su RUT NO se corregirá
-- 3. Después de ejecutar esto, los técnicos que NO se corrigieron
--    deberán agregarse manualmente a tecnicos_traza_zc
-- ══════════════════════════════════════════════════════════════════

