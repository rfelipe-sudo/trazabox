-- ═══════════════════════════════════════════════════════════════════
-- CORREGIR RUTs MAL CARGADOS EN ENERO Y FEBRERO - VERSIÓN 2
-- ═══════════════════════════════════════════════════════════════════
-- Sin tablas temporales - Ejecutar TODO de una vez
-- ═══════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════
-- PASO 1: Ver cuántos registros tienen problema
-- ══════════════════════════════════════════════════════════════════

SELECT 
    'ENERO 2026' as mes,
    COUNT(*) as registros_con_problema
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND (rut_tecnico IS NULL OR rut_tecnico = '' OR rut_tecnico LIKE '%-%-T%');

SELECT 
    'FEBRERO 2026' as mes,
    COUNT(*) as registros_con_problema
FROM produccion
WHERE (fecha_trabajo LIKE '%/02/26%' OR fecha_trabajo LIKE '%/02/2026%')
  AND (rut_tecnico IS NULL OR rut_tecnico = '' OR rut_tecnico LIKE '%-%-T%');

-- ══════════════════════════════════════════════════════════════════
-- PASO 2: ACTUALIZAR ENERO - Directamente con JOIN
-- ══════════════════════════════════════════════════════════════════

UPDATE produccion p
SET rut_tecnico = t.rut
FROM tecnicos_traza_zc t
WHERE LOWER(TRIM(p.tecnico)) = LOWER(TRIM(t.nombre_completo))
  AND (p.fecha_trabajo LIKE '%/01/26%' OR p.fecha_trabajo LIKE '%/01/2026%')
  AND (p.rut_tecnico IS NULL OR p.rut_tecnico = '' OR p.rut_tecnico LIKE '%-%-T%')
  AND t.rut IS NOT NULL
  AND t.rut != '';

-- ══════════════════════════════════════════════════════════════════
-- PASO 3: ACTUALIZAR FEBRERO - Directamente con JOIN
-- ══════════════════════════════════════════════════════════════════

UPDATE produccion p
SET rut_tecnico = t.rut
FROM tecnicos_traza_zc t
WHERE LOWER(TRIM(p.tecnico)) = LOWER(TRIM(t.nombre_completo))
  AND (p.fecha_trabajo LIKE '%/02/26%' OR p.fecha_trabajo LIKE '%/02/2026%')
  AND (p.rut_tecnico IS NULL OR p.rut_tecnico = '' OR p.rut_tecnico LIKE '%-%-T%')
  AND t.rut IS NOT NULL
  AND t.rut != '';

-- ══════════════════════════════════════════════════════════════════
-- PASO 4: VERIFICAR - Alberto Escalona en ENERO
-- ══════════════════════════════════════════════════════════════════

SELECT 
    rut_tecnico,
    COUNT(*) as ordenes,
    COUNT(*) FILTER (WHERE estado = 'Completado') as completadas,
    ROUND(SUM(rgu_total) FILTER (WHERE estado = 'Completado'), 2) as rgu_total
FROM produccion
WHERE tecnico = 'Alberto Escalona G'
  AND (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
GROUP BY rut_tecnico;

-- ══════════════════════════════════════════════════════════════════
-- PASO 5: VERIFICAR - Alberto Escalona en FEBRERO
-- ══════════════════════════════════════════════════════════════════

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
-- PASO 6: RESUMEN FINAL - Registros corregidos vs pendientes
-- ══════════════════════════════════════════════════════════════════

SELECT 
    'ENERO 2026' as mes,
    COUNT(*) FILTER (WHERE rut_tecnico IS NOT NULL AND rut_tecnico != '' AND rut_tecnico NOT LIKE '%-%-T%') as corregidos,
    COUNT(*) FILTER (WHERE rut_tecnico IS NULL OR rut_tecnico = '' OR rut_tecnico LIKE '%-%-T%') as aun_con_problema,
    COUNT(*) as total
FROM produccion
WHERE fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%'

UNION ALL

SELECT 
    'FEBRERO 2026' as mes,
    COUNT(*) FILTER (WHERE rut_tecnico IS NOT NULL AND rut_tecnico != '' AND rut_tecnico NOT LIKE '%-%-T%') as corregidos,
    COUNT(*) FILTER (WHERE rut_tecnico IS NULL OR rut_tecnico = '' OR rut_tecnico LIKE '%-%-T%') as aun_con_problema,
    COUNT(*) as total
FROM produccion
WHERE fecha_trabajo LIKE '%/02/26%' OR fecha_trabajo LIKE '%/02/2026%';

-- ══════════════════════════════════════════════════════════════════
-- PASO 7: Ver técnicos únicos con RUT corregido
-- ══════════════════════════════════════════════════════════════════

SELECT DISTINCT
    rut_tecnico,
    tecnico,
    COUNT(*) as ordenes_totales
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND rut_tecnico IS NOT NULL
  AND rut_tecnico != ''
  AND rut_tecnico NOT LIKE '%-%-T%'
GROUP BY rut_tecnico, tecnico
ORDER BY ordenes_totales DESC
LIMIT 20;

-- ══════════════════════════════════════════════════════════════════
-- NOTAS:
-- ══════════════════════════════════════════════════════════════════
/*
Este script:
1. ✅ Corrige RUTs vacíos o con timestamp en Enero y Febrero
2. ✅ Usa JOIN directo con tecnicos_traza_zc (sin tablas temporales)
3. ✅ Verifica que Alberto Escalona tenga RUT correcto
4. ✅ Muestra resumen de registros corregidos

IMPORTANTE:
- Ejecuta TODO el script de una vez (selecciona todo y RUN)
- NO ejecutes línea por línea
- Si algunos técnicos no se corrigen, es porque no están en tecnicos_traza_zc
*/

