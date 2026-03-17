-- ═══════════════════════════════════════════════════════════════════
-- SISTEMA COMPLETO DE TIEMPOS (INICIO TARDÍO + HORAS EXTRAS) - TRAZA V2
-- CON SOPORTE PARA MÚLTIPLES TURNOS
-- ═══════════════════════════════════════════════════════════════════
-- 
-- POLÍTICAS:
-- 
-- TURNO 5x2:
-- - Lunes a Viernes: 09:15 - 19:00
-- - Sábado: 10:00 - 14:00
-- - Inicio tardío: Después de 09:15 (L-V) o 10:00 (Sáb)
-- - Hora extra: Después de 19:00 (L-V) o 14:00 (Sáb)
-- 
-- TURNO 6x1:
-- - Lunes a Viernes: 09:45 - 18:30
-- - Sábado: 10:00 - 14:00
-- - Inicio tardío: Después de 09:45 (L-V) o 10:00 (Sáb)
-- - Hora extra: Después de 18:30 (L-V) o 14:00 (Sáb)
-- 
-- Domingo/Festivos: Todo el día = hora extra (ambos turnos)
-- ═══════════════════════════════════════════════════════════════════

-- ═════════════════════════════════════════════════════════════════
-- FUNCIÓN: CALCULAR MINUTOS DE INICIO TARDÍO (CON TURNO)
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calcular_minutos_inicio_tardio(
    p_fecha_trabajo TEXT,
    p_hora_inicio TEXT,
    p_tipo_turno TEXT DEFAULT '6x1'
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

    -- CASO 2: SÁBADO (6) - Inicio después de 10:00 (ambos turnos)
    IF v_dia_semana = 6 THEN
        v_hora_limite_num := 10.0;
        
        IF v_hora_inicio_num > v_hora_limite_num THEN
            v_minutos_tardio := ROUND((v_hora_inicio_num - v_hora_limite_num) * 60);
        END IF;

        RETURN GREATEST(v_minutos_tardio, 0);
    END IF;

    -- CASO 3: LUNES A VIERNES (1-5) - Depende del turno
    IF p_tipo_turno = '5x2' THEN
        v_hora_limite_num := 9.25; -- 09:15
    ELSE -- 6x1 o por defecto
        v_hora_limite_num := 9.75; -- 09:45
    END IF;

    IF v_hora_inicio_num > v_hora_limite_num THEN
        v_minutos_tardio := ROUND((v_hora_inicio_num - v_hora_limite_num) * 60);
    END IF;

    RETURN GREATEST(v_minutos_tardio, 0);
END;
$$ LANGUAGE plpgsql STABLE;

-- ═════════════════════════════════════════════════════════════════
-- FUNCIÓN: CALCULAR MINUTOS DE HORA EXTRA (CON TURNO)
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calcular_minutos_hora_extra(
    p_fecha_trabajo TEXT,
    p_hora_inicio TEXT,
    p_hora_fin TEXT,
    p_duracion_min INTEGER,
    p_tipo_turno TEXT DEFAULT '6x1'
)
RETURNS INTEGER AS $$
DECLARE
    v_fecha DATE;
    v_dia_semana INTEGER; -- 0=Domingo, 1=Lunes, ..., 6=Sábado
    v_hora_inicio_num NUMERIC;
    v_hora_fin_num NUMERIC;
    v_minutos_extra INTEGER := 0;
    v_limite_hora_num NUMERIC;
BEGIN
    -- Validar que tengamos datos
    IF p_fecha_trabajo IS NULL OR p_hora_fin IS NULL OR p_duracion_min IS NULL OR p_duracion_min = 0 THEN
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

    -- CASO 1: DOMINGO (0) o FESTIVO = TODO ES HORA EXTRA
    IF v_dia_semana = 0 OR es_festivo(v_fecha) THEN
        RETURN p_duracion_min;
    END IF;

    -- Convertir hora_fin a número (ej: "19:30" → 19.5)
    BEGIN
        v_hora_fin_num := SPLIT_PART(p_hora_fin, ':', 1)::NUMERIC + 
                          (SPLIT_PART(p_hora_fin, ':', 2)::NUMERIC / 60.0);
    EXCEPTION WHEN OTHERS THEN
        RETURN 0;
    END;

    -- CASO 2: SÁBADO (6) - Hora extra después de 14:00 (ambos turnos)
    IF v_dia_semana = 6 THEN
        v_limite_hora_num := 14.0;
        
        IF v_hora_fin_num > v_limite_hora_num THEN
            -- Convertir hora_inicio a número
            BEGIN
                v_hora_inicio_num := SPLIT_PART(p_hora_inicio, ':', 1)::NUMERIC + 
                                     (SPLIT_PART(p_hora_inicio, ':', 2)::NUMERIC / 60.0);
            EXCEPTION WHEN OTHERS THEN
                v_hora_inicio_num := v_limite_hora_num;
            END;

            -- Si inició antes del límite, solo contar después del límite
            IF v_hora_inicio_num < v_limite_hora_num THEN
                v_minutos_extra := ROUND((v_hora_fin_num - v_limite_hora_num) * 60);
            ELSE
                -- Si inició después del límite, toda la duración es hora extra
                v_minutos_extra := p_duracion_min;
            END IF;
        END IF;

        RETURN GREATEST(v_minutos_extra, 0);
    END IF;

    -- CASO 3: LUNES A VIERNES (1-5) - Depende del turno
    IF p_tipo_turno = '5x2' THEN
        v_limite_hora_num := 19.0; -- 19:00
    ELSE -- 6x1 o por defecto
        v_limite_hora_num := 18.5; -- 18:30
    END IF;

    IF v_hora_fin_num > v_limite_hora_num THEN
        -- Convertir hora_inicio a número
        BEGIN
            v_hora_inicio_num := SPLIT_PART(p_hora_inicio, ':', 1)::NUMERIC + 
                                 (SPLIT_PART(p_hora_inicio, ':', 2)::NUMERIC / 60.0);
        EXCEPTION WHEN OTHERS THEN
            v_hora_inicio_num := v_limite_hora_num;
        END;

        -- Si inició antes del límite, solo contar después del límite
        IF v_hora_inicio_num < v_limite_hora_num THEN
            v_minutos_extra := ROUND((v_hora_fin_num - v_limite_hora_num) * 60);
        ELSE
            -- Si inició después del límite, toda la duración es hora extra
            v_minutos_extra := p_duracion_min;
        END IF;
    END IF;

    RETURN GREATEST(v_minutos_extra, 0);
END;
$$ LANGUAGE plpgsql STABLE;

-- ═════════════════════════════════════════════════════════════════
-- VISTA: TIEMPOS COMPLETOS POR DÍA (CON TURNO)
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW v_tiempos_diarios AS
WITH ordenes_por_dia AS (
    SELECT
        p.rut_tecnico,
        p.tecnico,
        p.fecha_trabajo,
        TO_DATE(p.fecha_trabajo, 'DD/MM/YY') AS fecha_completa,
        EXTRACT(DOW FROM TO_DATE(p.fecha_trabajo, 'DD/MM/YY')) AS dia_semana,
        COALESCE(t.tipo_turno, '6x1') AS tipo_turno,
        MIN(p.hora_inicio) AS primera_orden_hora,
        MAX(p.hora_fin) AS ultima_orden_hora,
        COUNT(*) AS ordenes_completadas,
        -- Calcular inicio tardío de la PRIMERA orden del día (con turno)
        calcular_minutos_inicio_tardio(
            p.fecha_trabajo,
            MIN(p.hora_inicio),
            COALESCE(t.tipo_turno, '6x1')
        ) AS minutos_inicio_tardio
    FROM produccion p
    LEFT JOIN tecnicos_traza_zc t ON p.rut_tecnico = t.rut
    WHERE p.estado = 'Completado'
      AND p.rut_tecnico IS NOT NULL
      AND p.rut_tecnico != ''
      AND p.rut_tecnico NOT LIKE '%-%-T%'
      AND LENGTH(p.rut_tecnico) BETWEEN 9 AND 12
      AND p.hora_inicio IS NOT NULL
      AND p.hora_inicio != ''
    GROUP BY p.rut_tecnico, p.tecnico, p.fecha_trabajo, fecha_completa, dia_semana, t.tipo_turno
),
horas_extras_dia AS (
    SELECT
        p.rut_tecnico,
        p.fecha_trabajo,
        SUM(calcular_minutos_hora_extra(
            p.fecha_trabajo,
            p.hora_inicio,
            p.hora_fin,
            p.duracion_min,
            COALESCE(t.tipo_turno, '6x1')
        )) AS minutos_hora_extra
    FROM produccion p
    LEFT JOIN tecnicos_traza_zc t ON p.rut_tecnico = t.rut
    WHERE p.estado = 'Completado'
      AND p.rut_tecnico IS NOT NULL
      AND p.rut_tecnico != ''
      AND p.rut_tecnico NOT LIKE '%-%-T%'
      AND LENGTH(p.rut_tecnico) BETWEEN 9 AND 12
    GROUP BY p.rut_tecnico, p.fecha_trabajo, t.tipo_turno
)
SELECT
    opd.rut_tecnico,
    opd.tecnico,
    opd.tipo_turno,
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
    tipo_turno,
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
GROUP BY rut_tecnico, tecnico, tipo_turno, mes, anio
ORDER BY anio DESC, mes DESC, horas_extra_total DESC;

-- ═════════════════════════════════════════════════════════════════
-- VISTA: RESUMEN DE TIEMPOS PARA LA APP (POR TÉCNICO Y MES)
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW v_resumen_tiempos_app AS
SELECT
    rut_tecnico,
    tecnico,
    tipo_turno,
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

-- Prueba 1: Comparar cálculos entre turnos 5x2 y 6x1
SELECT 
    '🔍 COMPARACIÓN DE TURNOS' AS titulo,
    '5x2' AS turno,
    calcular_minutos_inicio_tardio('05/01/26', '09:30', '5x2') AS inicio_tardio_0930,
    calcular_minutos_hora_extra('05/01/26', '18:30', '19:15', 45, '5x2') AS hora_extra_1915
UNION ALL
SELECT 
    '🔍 COMPARACIÓN DE TURNOS' AS titulo,
    '6x1' AS turno,
    calcular_minutos_inicio_tardio('05/01/26', '09:30', '6x1') AS inicio_tardio_0930,
    calcular_minutos_hora_extra('05/01/26', '18:30', '19:15', 45, '6x1') AS hora_extra_1915;

-- Prueba 2: Ver tiempos diarios con tipo de turno
SELECT 
    '📊 TIEMPOS CON TURNO - Enero 2026' AS titulo,
    fecha_trabajo,
    tipo_turno,
    nombre_dia,
    primera_orden_hora,
    ultima_orden_hora,
    minutos_inicio_tardio,
    minutos_hora_extra,
    ordenes_completadas
FROM v_tiempos_diarios
WHERE EXTRACT(MONTH FROM fecha_completa) = 1
  AND EXTRACT(YEAR FROM fecha_completa) = 2026
ORDER BY fecha_completa DESC
LIMIT 10;

-- Prueba 3: Resumen por turno en Enero
SELECT 
    '📈 RESUMEN POR TURNO - Enero 2026' AS titulo,
    tipo_turno,
    COUNT(DISTINCT rut_tecnico) AS tecnicos,
    ROUND(AVG(horas_inicio_tardio_total), 2) AS promedio_inicio_tardio_hrs,
    ROUND(AVG(horas_extra_total), 2) AS promedio_horas_extra_hrs,
    ROUND(SUM(horas_inicio_tardio_total), 2) AS total_inicio_tardio_hrs,
    ROUND(SUM(horas_extra_total), 2) AS total_horas_extra_hrs
FROM v_tiempos_mensuales
WHERE mes = 1 AND anio = 2026
GROUP BY tipo_turno;

-- Prueba 4: Top 5 técnicos con más inicio tardío por turno
SELECT 
    '⏰ TOP 5 INICIO TARDÍO POR TURNO' AS titulo,
    tipo_turno,
    tecnico,
    dias_con_inicio_tardio,
    ROUND(horas_inicio_tardio_total, 2) AS horas_tardio
FROM (
    SELECT 
        tipo_turno,
        tecnico,
        dias_con_inicio_tardio,
        horas_inicio_tardio_total,
        ROW_NUMBER() OVER (PARTITION BY tipo_turno ORDER BY horas_inicio_tardio_total DESC) AS rn
    FROM v_tiempos_mensuales
    WHERE mes = 1 AND anio = 2026
      AND horas_inicio_tardio_total > 0
) AS ranked
WHERE rn <= 5
ORDER BY tipo_turno, horas_tardio DESC;

-- Prueba 5: Ejemplo práctico - Técnico específico
-- Cambiar '26402839-6' por el RUT del técnico que quieras verificar
SELECT 
    '🔍 DETALLE TÉCNICO ESPECÍFICO' AS titulo,
    rut_tecnico,
    tecnico,
    tipo_turno,
    minutos_inicio_tardio || 'm' AS inicio_tardio,
    minutos_hora_extra || 'm' AS horas_extras,
    dias_con_inicio_tardio,
    dias_con_hora_extra,
    dias_trabajados
FROM v_resumen_tiempos_app
WHERE rut_tecnico = '26402839-6'
  AND mes = 1
  AND anio = 2026;

