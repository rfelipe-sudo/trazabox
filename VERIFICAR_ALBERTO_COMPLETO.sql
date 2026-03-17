-- ═══════════════════════════════════════════════════════════════════
-- VERIFICAR: ¿Por qué Alberto solo tiene 20 órdenes en lugar de 95?
-- ═══════════════════════════════════════════════════════════════════

-- 1. Ver TODOS los registros de Alberto en Enero (por rut_tecnico)
SELECT 
    'Por RUT' as metodo,
    rut_tecnico,
    COUNT(*) as ordenes,
    ROUND(SUM(rgu_total), 2) as rgu_total,
    COUNT(*) FILTER (WHERE estado = 'Completado') as completadas
FROM produccion
WHERE rut_tecnico = '26402839-6'
  AND (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
GROUP BY rut_tecnico;

-- 2. Ver TODOS los registros de Alberto en Enero (por nombre)
SELECT 
    'Por Nombre' as metodo,
    rut_tecnico,
    COUNT(*) as ordenes,
    ROUND(SUM(rgu_total), 2) as rgu_total,
    COUNT(*) FILTER (WHERE estado = 'Completado') as completadas
FROM produccion
WHERE tecnico = 'Alberto Escalona G'
  AND (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
GROUP BY rut_tecnico;

-- 3. Ver desglose por tipo de rut_tecnico
SELECT 
    CASE 
        WHEN rut_tecnico = '26402839-6' THEN 'RUT Correcto'
        WHEN rut_tecnico LIKE '%-%-T%' THEN 'Timestamp'
        WHEN rut_tecnico IS NULL OR rut_tecnico = '' THEN 'Vacío'
        ELSE 'Otro: ' || rut_tecnico
    END as tipo_rut,
    COUNT(*) as ordenes,
    ROUND(SUM(rgu_total), 2) as rgu_total
FROM produccion
WHERE tecnico = 'Alberto Escalona G'
  AND (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
GROUP BY tipo_rut
ORDER BY ordenes DESC;

-- 4. Mostrar ejemplos de registros con RUT incorrecto
SELECT 
    rut_tecnico,
    tecnico,
    fecha_trabajo,
    orden_trabajo,
    estado,
    rgu_total
FROM produccion
WHERE tecnico = 'Alberto Escalona G'
  AND (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND rut_tecnico != '26402839-6'
LIMIT 10;

-- 5. Ver si existe en tecnicos_traza_zc
SELECT 
    rut,
    nombre_completo,
    activo,
    tipo_turno
FROM tecnicos_traza_zc
WHERE nombre_completo LIKE '%Alberto Escalona%'
   OR rut = '26402839-6';

