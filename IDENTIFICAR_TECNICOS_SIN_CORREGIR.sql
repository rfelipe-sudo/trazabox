-- ═══════════════════════════════════════════════════════════════════
-- IDENTIFICAR TÉCNICOS QUE AÚN TIENEN TIMESTAMPS EN ENERO
-- ═══════════════════════════════════════════════════════════════════

-- 1. Ver qué técnicos tienen timestamps o RUT vacío
SELECT 
    tecnico,
    COUNT(*) as ordenes_sin_corregir,
    ROUND(SUM(rgu_total), 2) as rgu_perdido,
    COUNT(DISTINCT rut_tecnico) as ruts_diferentes
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND (
    rut_tecnico LIKE '2026-%' 
    OR rut_tecnico LIKE '%T%' 
    OR rut_tecnico LIKE '%:%'
    OR rut_tecnico IS NULL 
    OR rut_tecnico = ''
  )
GROUP BY tecnico
ORDER BY ordenes_sin_corregir DESC;

-- 2. Verificar si esos técnicos existen en tecnicos_traza_zc
SELECT 
    p.tecnico as nombre_en_produccion,
    t.rut as rut_encontrado,
    t.nombre_completo as nombre_en_tecnicos_traza,
    COUNT(*) as ordenes_pendientes
FROM produccion p
LEFT JOIN tecnicos_traza_zc t ON LOWER(TRIM(p.tecnico)) = LOWER(TRIM(t.nombre_completo))
WHERE (p.fecha_trabajo LIKE '%/01/26%' OR p.fecha_trabajo LIKE '%/01/2026%')
  AND (
    p.rut_tecnico LIKE '2026-%' 
    OR p.rut_tecnico LIKE '%T%' 
    OR p.rut_tecnico LIKE '%:%'
    OR p.rut_tecnico IS NULL 
    OR p.rut_tecnico = ''
  )
GROUP BY p.tecnico, t.rut, t.nombre_completo
ORDER BY ordenes_pendientes DESC;

-- 3. Ver técnicos únicos en produccion vs tecnicos_traza_zc
SELECT 
    'Total técnicos únicos en Producción Enero' as descripcion,
    COUNT(DISTINCT tecnico) as cantidad
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')

UNION ALL

SELECT 
    'Total técnicos en tecnicos_traza_zc' as descripcion,
    COUNT(*) as cantidad
FROM tecnicos_traza_zc
WHERE activo = true;

