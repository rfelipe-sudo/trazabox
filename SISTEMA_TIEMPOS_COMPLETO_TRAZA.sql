-- ═══════════════════════════════════════════════════════════════════
-- SISTEMA COMPLETO DE TIEMPOS (INICIO TARDÍO + HORAS EXTRAS) - TRAZA
-- ═══════════════════════════════════════════════════════════════════
-- 
-- POLÍTICAS:
-- 
-- INICIO TARDÍO:
-- - Lunes a Viernes: Primera orden después de 09:45
-- - Sábado: Primera orden después de 10:00
-- - Domingo: No aplica (día libre)
-- 
-- HORAS EXTRAS:
-- - Lunes a Viernes: Después de 18:30
-- - Sábado: Después de 14:00
-- - Domingo/Festivos: Todo el día
-- ═══════════════════════════════════════════════════════════════════

-- ═════════════════════════════════════════════════════════════════
-- FUNCIÓN: CALCULAR MINUTOS DE INICIO TARDÍO
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calcular_minutos_inicio_tardio(
    p_fecha_trabajo TEXT,
    p_hora_inicio TEXT
)
RETURNS INTEGER AS $$
DECLARE
    v_fecha DATE;
    v_dia_semana INTEGER; -- 0=Domingo, 1=Lunes, ..., 6=Sábado
    v_hora_inicio_num NUMERIC;
    v_hora_limite_num NUMERIC;
    v_minutos_tardio INTEGER := 0;
BEGIN
    -- Validar que tengamos datos
    IF p_fecha_trabajo IS NULL OR p_hora_inicio IS NULL OR p_hora_inicio = '' THEN
        RETURN 0;
    END IF;

    -- Parsear fecha (formato DD/MM/YY)
    BEGIN
        v_fecha := TO_DATE(p_fecha_trabajo, 'DD/MM/YY');
    EXCEPTION WHEN OTHERS THEN
        RETURN 0;
    END;

    -- Obtener día de la semana (0=Domingo, 1=Lunes, ..., 6=Sábado)
    v_dia_semana := EXTRACT(DOW FROM v_fecha);

    -- CASO 1: DOMINGO (0) = No aplica inicio tardío (día libre)
    IF v_dia_semana = 0 THEN
        RETURN 0;
    END IF;

    -- Convertir hora_inicio a número (ej: "10:15" → 10.25)
    BEGIN
        v_hora_inicio_num := SPLIT_PART(p_hora_inicio, ':', 1)::NUMERIC + 
                             (SPLIT_PART(p_hora_inicio, ':', 2)::NUMERIC / 60.0);
    EXCEPTION WHEN OTHERS THEN
        RETURN 0;
    END;

    -- CASO 2: SÁBADO (6) - Inicio después de 10:00
    IF v_dia_semana = 6 THEN
        v_hora_limite_num := 10.0;
        
        IF v_hora_inicio_num > v_hora_limite_num THEN
            v_minutos_tardio := ROUND((v_hora_inicio_num - v_hora_limite_num) * 60);
        END IF;

        RETURN GREATEST(v_minutos_tardio, 0);
    END IF;

    -- CASO 3: LUNES A VIERNES (1-5) - Inicio después de 09:45
    v_hora_limite_num := 9.75; -- 09:45

    IF v_hora_inicio_num > v_hora_limite_num THEN
        v_minutos_tardio := ROUND((v_hora_inicio_num - v_hora_limite_num) * 60);
    END IF;

    RETURN GREATEST(v_minutos_tardio, 0);
END;
$$ LANGUAGE plpgsql STABLE;

-- ═════════════════════════════════════════════════════════════════
-- VISTA: TIEMPOS COMPLETOS POR DÍA (INICIO TARDÍO + HORAS EXTRAS)
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW v_tiempos_diarios AS
WITH ordenes_por_dia AS (
    SELECT
        p.rut_tecnico,
        p.tecnico,
        p.fecha_trabajo,
        TO_DATE(p.fecha_trabajo, 'DD/MM/YY') AS fecha_completa,
        EXTRACT(DOW FROM TO_DATE(p.fecha_trabajo, 'DD/MM/YY')) AS dia_semana,
        MIN(p.hora_inicio) AS primera_orden_hora,
        MAX(p.hora_fin) AS ultima_orden_hora,
        COUNT(*) AS ordenes_completadas,
        -- Calcular inicio tardío de la PRIMERA orden del día
        calcular_minutos_inicio_tardio(
            p.fecha_trabajo,
            MIN(p.hora_inicio)
        ) AS minutos_inicio_tardio
    FROM produccion p
    WHERE p.estado = 'Completado'
      AND p.rut_tecnico IS NOT NULL
      AND p.rut_tecnico != ''
      AND p.rut_tecnico NOT LIKE '%-%-T%'
      AND LENGTH(p.rut_tecnico) BETWEEN 9 AND 12
      AND p.hora_inicio IS NOT NULL
      AND p.hora_inicio != ''
    GROUP BY p.rut_tecnico, p.tecnico, p.fecha_trabajo, fecha_completa, dia_semana
),
horas_extras_dia AS (
    SELECT
        p.rut_tecnico,
        p.fecha_trabajo,
        SUM(calcular_minutos_hora_extra(
            p.fecha_trabajo,
            p.hora_inicio,
            p.hora_fin,
            p.duracion_min
        )) AS minutos_hora_extra
    FROM produccion p
    WHERE p.estado = 'Completado'
      AND p.rut_tecnico IS NOT NULL
      AND p.rut_tecnico != ''
      AND p.rut_tecnico NOT LIKE '%-%-T%'
      AND LENGTH(p.rut_tecnico) BETWEEN 9 AND 12
    GROUP BY p.rut_tecnico, p.fecha_trabajo
)
SELECT
    opd.rut_tecnico,
    opd.tecnico,
    opd.fecha_trabajo,
    opd.fecha_completa,
    opd.dia_semana,
    CASE 
        WHEN opd.dia_semana = 0 THEN 'Domingo'
        WHEN opd.dia_semana = 1 THEN 'Lunes'
        WHEN opd.dia_semana = 2 THEN 'Martes'
        WHEN opd.dia_semana = 3 THEN 'Miércoles'
        WHEN opd.dia_semana = 4 THEN 'Jueves'
        WHEN opd.dia_semana = 5 THEN 'Viernes'
        WHEN opd.dia_semana = 6 THEN 'Sábado'
    END AS nombre_dia,
    opd.ordenes_completadas,
    opd.primera_orden_hora,
    opd.ultima_orden_hora,
    -- INICIO TARDÍO
    opd.minutos_inicio_tardio,
    ROUND(opd.minutos_inicio_tardio / 60.0, 2) AS horas_inicio_tardio,
    -- HORAS EXTRAS
    COALESCE(hed.minutos_hora_extra, 0) AS minutos_hora_extra,
    ROUND(COALESCE(hed.minutos_hora_extra, 0) / 60.0, 2) AS horas_extra
FROM ordenes_por_dia opd
LEFT JOIN horas_extras_dia hed 
    ON opd.rut_tecnico = hed.rut_tecnico 
    AND opd.fecha_trabajo = hed.fecha_trabajo
ORDER BY opd.fecha_completa DESC, opd.rut_tecnico;

-- ═════════════════════════════════════════════════════════════════
-- VISTA: TIEMPOS ACUMULADOS POR MES
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW v_tiempos_mensuales AS
SELECT
    rut_tecnico,
    tecnico,
    EXTRACT(MONTH FROM fecha_completa) AS mes,
    EXTRACT(YEAR FROM fecha_completa) AS anio,
    -- INICIO TARDÍO
    COUNT(*) FILTER (WHERE minutos_inicio_tardio > 0) AS dias_con_inicio_tardio,
    SUM(minutos_inicio_tardio) AS minutos_inicio_tardio_total,
    ROUND(SUM(minutos_inicio_tardio) / 60.0, 2) AS horas_inicio_tardio_total,
    -- HORAS EXTRAS
    COUNT(*) FILTER (WHERE minutos_hora_extra > 0) AS dias_con_hora_extra,
    SUM(minutos_hora_extra) AS minutos_hora_extra_total,
    ROUND(SUM(minutos_hora_extra) / 60.0, 2) AS horas_extra_total,
    -- RESUMEN
    COUNT(DISTINCT fecha_trabajo) AS dias_trabajados,
    SUM(ordenes_completadas) AS ordenes_totales,
    MIN(fecha_completa) AS primera_fecha,
    MAX(fecha_completa) AS ultima_fecha
FROM v_tiempos_diarios
GROUP BY rut_tecnico, tecnico, mes, anio
ORDER BY anio DESC, mes DESC, horas_extra_total DESC;

-- ═════════════════════════════════════════════════════════════════
-- VISTA: RESUMEN DE TIEMPOS PARA LA APP (POR TÉCNICO Y MES)
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW v_resumen_tiempos_app AS
SELECT
    rut_tecnico,
    tecnico,
    mes,
    anio,
    -- INICIO TARDÍO (para mostrar en la tarjeta roja)
    minutos_inicio_tardio_total AS minutos_inicio_tardio,
    horas_inicio_tardio_total AS horas_inicio_tardio,
    dias_con_inicio_tardio,
    -- HORAS EXTRAS (para mostrar en la tarjeta azul)
    minutos_hora_extra_total AS minutos_hora_extra,
    horas_extra_total AS horas_extra,
    dias_con_hora_extra,
    -- OTROS
    dias_trabajados,
    ordenes_totales
FROM v_tiempos_mensuales;

-- ═════════════════════════════════════════════════════════════════
-- PRUEBAS DE VERIFICACIÓN
-- ═════════════════════════════════════════════════════════════════

-- Prueba 1: Ver tiempos diarios de Alberto Escalona en Enero 2026
SELECT 
    '📊 TIEMPOS DIARIOS - Alberto Escalona' AS titulo,
    fecha_trabajo,
    nombre_dia,
    primera_orden_hora,
    ultima_orden_hora,
    minutos_inicio_tardio,
    minutos_hora_extra,
    ordenes_completadas
FROM v_tiempos_diarios
WHERE rut_tecnico = '26402839-6'
  AND EXTRACT(MONTH FROM fecha_completa) = 1
  AND EXTRACT(YEAR FROM fecha_completa) = 2026
ORDER BY fecha_completa;

-- Prueba 2: Resumen mensual de Alberto
SELECT 
    '📈 RESUMEN MENSUAL - Alberto Escalona' AS titulo,
    dias_con_inicio_tardio,
    horas_inicio_tardio_total,
    dias_con_hora_extra,
    horas_extra_total,
    dias_trabajados,
    ordenes_totales
FROM v_tiempos_mensuales
WHERE rut_tecnico = '26402839-6'
  AND mes = 1
  AND anio = 2026;

-- Prueba 3: Vista para la APP (formato directo)
SELECT 
    '📱 FORMATO PARA APP - Alberto Escalona' AS titulo,
    minutos_inicio_tardio || 'm' AS inicio_tardio,
    minutos_hora_extra || 'm' AS horas_extras,
    dias_con_inicio_tardio AS dias_tardio,
    dias_con_hora_extra AS dias_extra
FROM v_resumen_tiempos_app
WHERE rut_tecnico = '26402839-6'
  AND mes = 1
  AND anio = 2026;

-- Prueba 4: Top 10 técnicos con más inicio tardío
SELECT 
    '⏰ TOP 10 INICIO TARDÍO - Enero 2026' AS titulo,
    ROW_NUMBER() OVER (ORDER BY horas_inicio_tardio_total DESC) AS posicion,
    tecnico,
    dias_con_inicio_tardio,
    ROUND(horas_inicio_tardio_total, 2) AS horas_tardio
FROM v_tiempos_mensuales
WHERE mes = 1 AND anio = 2026
  AND horas_inicio_tardio_total > 0
ORDER BY horas_inicio_tardio_total DESC
LIMIT 10;

-- Prueba 5: Top 10 técnicos con más horas extras
SELECT 
    '⏳ TOP 10 HORAS EXTRAS - Enero 2026' AS titulo,
    ROW_NUMBER() OVER (ORDER BY horas_extra_total DESC) AS posicion,
    tecnico,
    dias_con_hora_extra,
    ROUND(horas_extra_total, 2) AS horas_extra
FROM v_tiempos_mensuales
WHERE mes = 1 AND anio = 2026
  AND horas_extra_total > 0
ORDER BY horas_extra_total DESC
LIMIT 10;

-- Prueba 6: Ejemplo específico - Primera orden tarde un día específico
SELECT 
    '🔍 EJEMPLO INICIO TARDÍO - Alberto 07/01/26' AS titulo,
    fecha_trabajo,
    primera_orden_hora,
    CASE 
        WHEN nombre_dia IN ('Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes') 
            THEN '09:45'
        WHEN nombre_dia = 'Sábado'
            THEN '10:00'
        ELSE 'No aplica'
    END AS hora_esperada,
    minutos_inicio_tardio,
    CASE 
        WHEN minutos_inicio_tardio > 0 
            THEN '⚠️ Inició tarde'
        ELSE '✅ A tiempo'
    END AS resultado
FROM v_tiempos_diarios
WHERE rut_tecnico = '26402839-6'
  AND fecha_trabajo = '07/01/26';

-- Prueba 7: Estadísticas generales de tiempos en Enero
SELECT 
    '📊 ESTADÍSTICAS GENERALES ENERO 2026' AS titulo,
    COUNT(DISTINCT rut_tecnico) AS tecnicos_total,
    COUNT(DISTINCT rut_tecnico) FILTER (WHERE horas_inicio_tardio_total > 0) AS tecnicos_con_tardanza,
    COUNT(DISTINCT rut_tecnico) FILTER (WHERE horas_extra_total > 0) AS tecnicos_con_hora_extra,
    ROUND(AVG(horas_inicio_tardio_total), 2) AS promedio_horas_tardio,
    ROUND(AVG(horas_extra_total), 2) AS promedio_horas_extra,
    ROUND(SUM(horas_inicio_tardio_total), 2) AS total_horas_tardio_empresa,
    ROUND(SUM(horas_extra_total), 2) AS total_horas_extra_empresa
FROM v_tiempos_mensuales
WHERE mes = 1 AND anio = 2026;

