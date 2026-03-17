-- ═══════════════════════════════════════════════════════════════════
-- RECREAR VISTA DE RANKING - VERSIÓN CORREGIDA FINAL
-- ═══════════════════════════════════════════════════════════════════

-- Eliminar vista existente
DROP VIEW IF EXISTS v_ranking_produccion CASCADE;

-- Crear vista nueva con filtro correcto
CREATE VIEW v_ranking_produccion AS
WITH produccion_limpia AS (
    -- Filtrar solo registros con RUT válido
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
      AND p.rut_tecnico NOT LIKE '%-%-T%'  -- Excluir timestamps
      AND p.rut_tecnico NOT LIKE '%:%'     -- Excluir cualquier cosa con :
      AND LENGTH(p.rut_tecnico) BETWEEN 9 AND 12  -- RUT chileno: 12345678-9
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

-- ══════════════════════════════════════════════════════════════════
-- VERIFICACIONES
-- ══════════════════════════════════════════════════════════════════

-- 1. Ver top 10 de Enero 2026
SELECT 
    ranking,
    rut_tecnico,
    tecnico,
    rgu_total,
    ordenes_completadas,
    dias_operativos,
    promedio_rgu_dia
FROM v_ranking_produccion
WHERE mes = 1 AND anio = 2026
ORDER BY ranking
LIMIT 10;

-- 2. Buscar Alberto Escalona específicamente
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

-- 3. Verificar que NO haya timestamps
SELECT 
    rut_tecnico,
    COUNT(*) as cantidad
FROM v_ranking_produccion
WHERE mes = 1 AND anio = 2026
  AND rut_tecnico LIKE '%-%T%'
GROUP BY rut_tecnico;

-- 4. Contar técnicos únicos en Enero
SELECT 
    COUNT(DISTINCT rut_tecnico) as tecnicos_unicos,
    COUNT(*) as registros_totales
FROM v_ranking_produccion
WHERE mes = 1 AND anio = 2026;

-- 5. Ver resumen por ranking
SELECT 
    ranking,
    COUNT(*) as cantidad_tecnicos,
    MIN(promedio_rgu_dia) as promedio_minimo,
    MAX(promedio_rgu_dia) as promedio_maximo
FROM v_ranking_produccion
WHERE mes = 1 AND anio = 2026
GROUP BY ranking
ORDER BY ranking
LIMIT 10;

