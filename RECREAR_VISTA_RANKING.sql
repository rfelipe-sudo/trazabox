-- ═══════════════════════════════════════════════════════════════════
-- RECREAR VISTA DE RANKING - Para actualizar con RUTs corregidos
-- ═══════════════════════════════════════════════════════════════════

-- Eliminar vista existente
DROP VIEW IF EXISTS v_ranking_produccion;

-- Recrear vista con RUTs correctos
CREATE VIEW v_ranking_produccion AS
WITH tecnicos_mes AS (
    SELECT DISTINCT
        p.rut_tecnico,
        p.tecnico,
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
),
rgu_por_tecnico AS (
    SELECT 
        tm.rut_tecnico,
        tm.tecnico,
        tm.mes,
        tm.anio,
        tm.tipo_turno,
        COALESCE(SUM(p.rgu_total), 0) as rgu_total,
        COUNT(*) as ordenes_completadas
    FROM tecnicos_mes tm
    LEFT JOIN produccion p ON 
        p.rut_tecnico = tm.rut_tecnico
        AND p.estado = 'Completado'
        AND (
            p.fecha_trabajo LIKE '%/' || tm.mes::TEXT || '/' || tm.anio::TEXT
            OR p.fecha_trabajo LIKE '%/' || LPAD(tm.mes::TEXT, 2, '0') || '/' || tm.anio::TEXT
            OR p.fecha_trabajo LIKE '%/' || tm.mes::TEXT || '/' || RIGHT(tm.anio::TEXT, 2)
            OR p.fecha_trabajo LIKE '%/' || LPAD(tm.mes::TEXT, 2, '0') || '/' || RIGHT(tm.anio::TEXT, 2)
        )
    GROUP BY tm.rut_tecnico, tm.tecnico, tm.mes, tm.anio, tm.tipo_turno
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
FROM rgu_por_tecnico
WHERE rgu_total > 0
ORDER BY mes DESC, anio DESC, promedio_rgu_dia DESC;

-- Verificar con Alberto Escalona
SELECT 
    ranking,
    rut_tecnico,
    tecnico,
    tipo_turno,
    rgu_total,
    ordenes_completadas,
    dias_operativos,
    promedio_rgu_dia
FROM v_ranking_produccion
WHERE tecnico = 'Alberto Escalona G'
  AND mes = 1 
  AND anio = 2026;

-- Ver top 10 enero 2026
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

