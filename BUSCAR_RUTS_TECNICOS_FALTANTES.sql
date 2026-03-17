-- ═══════════════════════════════════════════════════════════════════
-- BUSCAR RUTs DE LOS 7 TÉCNICOS FALTANTES
-- ═══════════════════════════════════════════════════════════════════

-- Buscar en TODOS los registros de producción si tienen RUT válido en algún mes
SELECT 
    tecnico,
    rut_tecnico,
    COUNT(*) as registros_con_este_rut,
    MIN(fecha_trabajo) as primera_fecha,
    MAX(fecha_trabajo) as ultima_fecha
FROM produccion
WHERE tecnico IN (
    'Fernando Veloso Martinez',
    'Kenny Ramirez B',
    'Carlos Fuentealba V',
    'Carlos Garcia N',
    'Pablo Jara N',
    'Pablo Balboa M',
    'Roy Mancilla Jimenez'
)
AND rut_tecnico IS NOT NULL
AND rut_tecnico != ''
AND rut_tecnico NOT LIKE '2026-%'
AND rut_tecnico NOT LIKE '%T%'
AND rut_tecnico NOT LIKE '%:%'
AND LENGTH(rut_tecnico) BETWEEN 9 AND 12
GROUP BY tecnico, rut_tecnico
ORDER BY tecnico, registros_con_este_rut DESC;

-- Ver TODOS los rut_tecnico que tienen (incluyendo timestamps)
SELECT 
    tecnico,
    rut_tecnico,
    COUNT(*) as cantidad,
    CASE 
        WHEN rut_tecnico LIKE '2026-%' OR rut_tecnico LIKE '%T%' OR rut_tecnico LIKE '%:%' THEN '❌ Timestamp'
        WHEN rut_tecnico IS NULL OR rut_tecnico = '' THEN '❌ Vacío'
        WHEN LENGTH(rut_tecnico) BETWEEN 9 AND 12 THEN '✅ RUT válido'
        ELSE '⚠️ Otro'
    END as tipo
FROM produccion
WHERE tecnico IN (
    'Fernando Veloso Martinez',
    'Kenny Ramirez B',
    'Carlos Fuentealba V',
    'Carlos Garcia N',
    'Pablo Jara N',
    'Pablo Balboa M',
    'Roy Mancilla Jimenez'
)
GROUP BY tecnico, rut_tecnico, tipo
ORDER BY tecnico, cantidad DESC;

