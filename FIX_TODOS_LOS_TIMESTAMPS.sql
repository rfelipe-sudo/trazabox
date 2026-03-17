-- ═══════════════════════════════════════════════════════════════════
-- CORREGIR TODOS LOS TIMESTAMPS EN rut_tecnico
-- ═══════════════════════════════════════════════════════════════════
-- Los timestamps tienen formato: 2026-01-05T08:00:00.000Z
-- Necesitamos reemplazarlos con el RUT correcto
-- ═══════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════
-- PASO 1: Ver cuántos registros tienen timestamps (cualquier formato)
-- ══════════════════════════════════════════════════════════════════

SELECT 
    'Enero con fecha en rut_tecnico' as tipo,
    COUNT(*) as cantidad
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND (rut_tecnico LIKE '2026-%' OR rut_tecnico LIKE '%T%' OR rut_tecnico LIKE '%:%');

SELECT 
    'Febrero con fecha en rut_tecnico' as tipo,
    COUNT(*) as cantidad
FROM produccion
WHERE (fecha_trabajo LIKE '%/02/26%' OR fecha_trabajo LIKE '%/02/2026%')
  AND (rut_tecnico LIKE '2026-%' OR rut_tecnico LIKE '%T%' OR rut_tecnico LIKE '%:%');

-- ══════════════════════════════════════════════════════════════════
-- PASO 2: ACTUALIZAR ENERO - Todos los que tengan fecha en lugar de RUT
-- ══════════════════════════════════════════════════════════════════

UPDATE produccion p
SET rut_tecnico = t.rut
FROM tecnicos_traza_zc t
WHERE LOWER(TRIM(p.tecnico)) = LOWER(TRIM(t.nombre_completo))
  AND (p.fecha_trabajo LIKE '%/01/26%' OR p.fecha_trabajo LIKE '%/01/2026%')
  AND (
    p.rut_tecnico LIKE '2026-%' 
    OR p.rut_tecnico LIKE '%T%' 
    OR p.rut_tecnico LIKE '%:%'
    OR p.rut_tecnico IS NULL 
    OR p.rut_tecnico = ''
  )
  AND t.rut IS NOT NULL
  AND t.rut != '';

-- ══════════════════════════════════════════════════════════════════
-- PASO 3: ACTUALIZAR FEBRERO - Todos los que tengan fecha en lugar de RUT
-- ══════════════════════════════════════════════════════════════════

UPDATE produccion p
SET rut_tecnico = t.rut
FROM tecnicos_traza_zc t
WHERE LOWER(TRIM(p.tecnico)) = LOWER(TRIM(t.nombre_completo))
  AND (p.fecha_trabajo LIKE '%/02/26%' OR p.fecha_trabajo LIKE '%/02/2026%')
  AND (
    p.rut_tecnico LIKE '2026-%' 
    OR p.rut_tecnico LIKE '%T%' 
    OR p.rut_tecnico LIKE '%:%'
    OR p.rut_tecnico IS NULL 
    OR p.rut_tecnico = ''
  )
  AND t.rut IS NOT NULL
  AND t.rut != '';

-- ══════════════════════════════════════════════════════════════════
-- PASO 4: VERIFICAR - Alberto Escalona en ENERO
-- ══════════════════════════════════════════════════════════════════

SELECT 
    rut_tecnico,
    COUNT(*) as ordenes,
    ROUND(SUM(rgu_total), 2) as rgu_total,
    COUNT(*) FILTER (WHERE estado = 'Completado') as completadas
FROM produccion
WHERE tecnico = 'Alberto Escalona G'
  AND (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
GROUP BY rut_tecnico;

-- ══════════════════════════════════════════════════════════════════
-- PASO 5: VERIFICAR - Desglose por tipo de RUT
-- ══════════════════════════════════════════════════════════════════

SELECT 
    CASE 
        WHEN rut_tecnico = '26402839-6' THEN '✅ RUT Correcto'
        WHEN rut_tecnico LIKE '2026-%' THEN '❌ Timestamp'
        WHEN rut_tecnico LIKE '%T%' THEN '❌ Timestamp con T'
        WHEN rut_tecnico LIKE '%:%' THEN '❌ Timestamp con hora'
        WHEN rut_tecnico IS NULL OR rut_tecnico = '' THEN '❌ Vacío'
        ELSE '⚠️ Otro: ' || rut_tecnico
    END as tipo_rut,
    COUNT(*) as ordenes,
    ROUND(SUM(rgu_total), 2) as rgu_total
FROM produccion
WHERE tecnico = 'Alberto Escalona G'
  AND (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
GROUP BY tipo_rut
ORDER BY ordenes DESC;

-- ══════════════════════════════════════════════════════════════════
-- PASO 6: RESUMEN GENERAL - Enero y Febrero
-- ══════════════════════════════════════════════════════════════════

SELECT 
    'ENERO 2026' as mes,
    COUNT(*) FILTER (WHERE rut_tecnico NOT LIKE '2026-%' AND rut_tecnico NOT LIKE '%T%' AND rut_tecnico NOT LIKE '%:%' AND rut_tecnico IS NOT NULL AND rut_tecnico != '') as con_rut_correcto,
    COUNT(*) FILTER (WHERE rut_tecnico LIKE '2026-%' OR rut_tecnico LIKE '%T%' OR rut_tecnico LIKE '%:%') as con_timestamp,
    COUNT(*) FILTER (WHERE rut_tecnico IS NULL OR rut_tecnico = '') as vacios,
    COUNT(*) as total
FROM produccion
WHERE fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%'

UNION ALL

SELECT 
    'FEBRERO 2026' as mes,
    COUNT(*) FILTER (WHERE rut_tecnico NOT LIKE '2026-%' AND rut_tecnico NOT LIKE '%T%' AND rut_tecnico NOT LIKE '%:%' AND rut_tecnico IS NOT NULL AND rut_tecnico != '') as con_rut_correcto,
    COUNT(*) FILTER (WHERE rut_tecnico LIKE '2026-%' OR rut_tecnico LIKE '%T%' OR rut_tecnico LIKE '%:%') as con_timestamp,
    COUNT(*) FILTER (WHERE rut_tecnico IS NULL OR rut_tecnico = '') as vacios,
    COUNT(*) as total
FROM produccion
WHERE fecha_trabajo LIKE '%/02/26%' OR fecha_trabajo LIKE '%/02/2026%';

-- ══════════════════════════════════════════════════════════════════
-- PASO 7: Recrear vista de ranking (para que actualice)
-- ══════════════════════════════════════════════════════════════════

DROP VIEW IF EXISTS v_ranking_produccion CASCADE;

CREATE VIEW v_ranking_produccion AS
WITH produccion_limpia AS (
    SELECT 
        p.rut_tecnico,
        p.tecnico,
        p.fecha_trabajo,
        p.rgu_total,
        p.estado,
        CAST(SPLIT_PART(p.fecha_trabajo, '/', 2) AS INTEGER) as mes,
        CASE 
            WHEN LENGTH(SPLIT_PART(p.fecha_trabajo, '/', 3)) = 2 
            THEN 2000 + CAST(SPLIT_PART(p.fecha_trabajo, '/', 3) AS INTEGER)
            ELSE CAST(SPLIT_PART(p.fecha_trabajo, '/', 3) AS INTEGER)
        END as anio,
        COALESCE(t.tipo_turno, '5x2') as tipo_turno
    FROM produccion p
    LEFT JOIN tecnicos_traza_zc t ON p.rut_tecnico = t.rut
    WHERE p.estado = 'Completado'
      AND p.rut_tecnico IS NOT NULL 
      AND p.rut_tecnico != ''
      AND p.rut_tecnico NOT LIKE '2026-%'
      AND p.rut_tecnico NOT LIKE '%T%'
      AND p.rut_tecnico NOT LIKE '%:%'
      AND LENGTH(p.rut_tecnico) BETWEEN 9 AND 12
),
resumen_por_tecnico AS (
    SELECT 
        rut_tecnico,
        tecnico,
        mes,
        anio,
        tipo_turno,
        SUM(rgu_total) as rgu_total,
        COUNT(*) as ordenes_completadas
    FROM produccion_limpia
    GROUP BY rut_tecnico, tecnico, mes, anio, tipo_turno
)
SELECT 
    rut_tecnico,
    tecnico,
    mes,
    anio,
    tipo_turno,
    rgu_total,
    ordenes_completadas,
    calcular_dias_operativos(mes, anio, tipo_turno) as dias_operativos,
    ROUND(rgu_total / NULLIF(calcular_dias_operativos(mes, anio, tipo_turno), 0), 2) as promedio_rgu_dia,
    DENSE_RANK() OVER (
        PARTITION BY mes, anio 
        ORDER BY ROUND(rgu_total / NULLIF(calcular_dias_operativos(mes, anio, tipo_turno), 0), 2) DESC
    ) as ranking
FROM resumen_por_tecnico
WHERE rgu_total > 0
ORDER BY mes DESC, anio DESC, promedio_rgu_dia DESC;

-- Ver ranking actualizado de Alberto
SELECT 
    ranking,
    rut_tecnico,
    tecnico,
    rgu_total,
    ordenes_completadas,
    dias_operativos,
    promedio_rgu_dia
FROM v_ranking_produccion
WHERE tecnico LIKE '%Alberto Escalona%'
  AND mes = 1 
  AND anio = 2026;

/*
RESULTADOS ESPERADOS:

PASO 4 - Alberto debe mostrar:
| rut_tecnico | ordenes | rgu_total | completadas |
|-------------|---------|-----------|-------------|
| 26402839-6  | 95      | ~106.00   | 95          |

PASO 5 - Debe mostrar solo:
| tipo_rut        | ordenes | rgu_total |
|-----------------|---------|-----------|
| ✅ RUT Correcto | 95      | ~106.00   |

PASO 6 - Enero debe mostrar:
| mes        | con_rut_correcto | con_timestamp | vacios | total |
|------------|------------------|---------------|--------|-------|
| ENERO 2026 | ~2238            | 0             | 0      | ~2238 |

ÚLTIMO SELECT - Alberto debe tener ranking ~13-15 con promedio ~4.82
*/

