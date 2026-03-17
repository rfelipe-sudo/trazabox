-- ═══════════════════════════════════════════════════════════════════
-- DIAGNÓSTICO: ESTADOS DE ÓRDENES EN PRODUCCIÓN
-- ═══════════════════════════════════════════════════════════════════

-- 1. Ver TODOS los estados únicos en la tabla produccion
SELECT 
    estado,
    COUNT(*) AS cantidad
FROM produccion
WHERE fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%'
GROUP BY estado
ORDER BY cantidad DESC;

-- 2. Ver estados para un técnico específico (reemplaza con el RUT del técnico)
-- Ejemplo: '26402839-6' (Alberto Escalona)
SELECT 
    rut_tecnico,
    tecnico,
    estado,
    COUNT(*) AS cantidad,
    ROUND(SUM(rgu_total), 2) AS rgu_total
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND rut_tecnico = '26402839-6'  -- 👈 CAMBIAR POR EL RUT DEL TÉCNICO
GROUP BY rut_tecnico, tecnico, estado
ORDER BY cantidad DESC;

-- 3. Ver ejemplos de órdenes con estado diferente a "Completado"
SELECT 
    rut_tecnico,
    tecnico,
    fecha_trabajo,
    orden_trabajo,
    estado,
    tipo_orden,
    rgu_total
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND estado != 'Completado'
ORDER BY fecha_trabajo DESC, tecnico
LIMIT 20;

-- 4. Contar por estado (case-insensitive)
SELECT 
    LOWER(estado) AS estado_normalizado,
    estado AS estado_original,
    COUNT(*) AS cantidad
FROM produccion
WHERE fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%'
GROUP BY LOWER(estado), estado
ORDER BY cantidad DESC;

-- 5. Buscar estados que contengan palabras clave
SELECT 
    'Contiene "cancel"' AS tipo,
    COUNT(*) AS cantidad
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND LOWER(estado) LIKE '%cancel%'
UNION ALL
SELECT 
    'Contiene "no realiz"' AS tipo,
    COUNT(*) AS cantidad
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND LOWER(estado) LIKE '%no realiz%'
UNION ALL
SELECT 
    'Contiene "suspend"' AS tipo,
    COUNT(*) AS cantidad
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND LOWER(estado) LIKE '%suspend%'
UNION ALL
SELECT 
    'Contiene "anul"' AS tipo,
    COUNT(*) AS cantidad
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND LOWER(estado) LIKE '%anul%';

