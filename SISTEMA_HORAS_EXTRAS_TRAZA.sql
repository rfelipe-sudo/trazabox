-- ═══════════════════════════════════════════════════════════════════
-- SISTEMA DE CÁLCULO DE HORAS EXTRAS PARA TRAZA
-- ═══════════════════════════════════════════════════════════════════
-- 
-- POLÍTICA:
-- - Lunes a Viernes: Después de 18:30 = hora extra
-- - Sábado: Después de 14:00 = hora extra
-- - Domingo/Festivos: Todo el día = hora extra
-- - Condición: Última orden a máx 300m del domicilio (FASE 2)
-- ═══════════════════════════════════════════════════════════════════

-- ═════════════════════════════════════════════════════════════════
-- PASO 1: AÑADIR COLUMNAS PARA DOMICILIO EN tecnicos_traza_zc
-- ═════════════════════════════════════════════════════════════════

DO $$
BEGIN
    -- Añadir dirección del domicilio
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'tecnicos_traza_zc' AND column_name = 'direccion_domicilio'
    ) THEN
        ALTER TABLE tecnicos_traza_zc ADD COLUMN direccion_domicilio TEXT;
        RAISE NOTICE '✅ Columna direccion_domicilio añadida';
    ELSE
        RAISE NOTICE '⚠️ Columna direccion_domicilio ya existe';
    END IF;

    -- Añadir coordenada X del domicilio
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'tecnicos_traza_zc' AND column_name = 'coord_domicilio_x'
    ) THEN
        ALTER TABLE tecnicos_traza_zc ADD COLUMN coord_domicilio_x NUMERIC;
        RAISE NOTICE '✅ Columna coord_domicilio_x añadida';
    ELSE
        RAISE NOTICE '⚠️ Columna coord_domicilio_x ya existe';
    END IF;

    -- Añadir coordenada Y del domicilio
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'tecnicos_traza_zc' AND column_name = 'coord_domicilio_y'
    ) THEN
        ALTER TABLE tecnicos_traza_zc ADD COLUMN coord_domicilio_y NUMERIC;
        RAISE NOTICE '✅ Columna coord_domicilio_y añadida';
    ELSE
        RAISE NOTICE '⚠️ Columna coord_domicilio_y ya existe';
    END IF;
END $$;

-- ═════════════════════════════════════════════════════════════════
-- PASO 2: FUNCIÓN PARA CALCULAR DISTANCIA GEOGRÁFICA (HAVERSINE)
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calcular_distancia_metros(
    lat1 NUMERIC,
    lon1 NUMERIC,
    lat2 NUMERIC,
    lon2 NUMERIC
)
RETURNS NUMERIC AS $$
DECLARE
    radio_tierra CONSTANT NUMERIC := 6371000; -- Radio de la Tierra en metros
    dlat NUMERIC;
    dlon NUMERIC;
    a NUMERIC;
    c NUMERIC;
    distancia NUMERIC;
BEGIN
    -- Si alguna coordenada es NULL, retornar NULL
    IF lat1 IS NULL OR lon1 IS NULL OR lat2 IS NULL OR lon2 IS NULL THEN
        RETURN NULL;
    END IF;

    -- Convertir grados a radianes
    dlat := RADIANS(lat2 - lat1);
    dlon := RADIANS(lon2 - lon1);

    -- Fórmula de Haversine
    a := SIN(dlat/2) * SIN(dlat/2) + 
         COS(RADIANS(lat1)) * COS(RADIANS(lat2)) * 
         SIN(dlon/2) * SIN(dlon/2);
    c := 2 * ATAN2(SQRT(a), SQRT(1-a));
    distancia := radio_tierra * c;

    RETURN ROUND(distancia, 2);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ═════════════════════════════════════════════════════════════════
-- PASO 3: FUNCIÓN PARA DETERMINAR SI ES DÍA FESTIVO
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION es_festivo(p_fecha DATE)
RETURNS BOOLEAN AS $$
DECLARE
    v_es_festivo BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM festivos_chile WHERE fecha = p_fecha
    ) INTO v_es_festivo;
    
    RETURN v_es_festivo;
END;
$$ LANGUAGE plpgsql STABLE;

-- ═════════════════════════════════════════════════════════════════
-- PASO 4: FUNCIÓN PARA CALCULAR MINUTOS DE HORA EXTRA DE UNA ORDEN
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calcular_minutos_hora_extra(
    p_fecha_trabajo TEXT,
    p_hora_inicio TEXT,
    p_hora_fin TEXT,
    p_duracion_min INTEGER
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

    -- CASO 2: SÁBADO (6) - Hora extra después de 14:00
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

    -- CASO 3: LUNES A VIERNES (1-5) - Hora extra después de 18:30
    v_limite_hora_num := 18.5; -- 18:30

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
-- PASO 5: VISTA DE HORAS EXTRAS POR TÉCNICO Y DÍA
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW v_horas_extras_diarias AS
SELECT
    p.rut_tecnico,
    p.tecnico,
    p.fecha_trabajo,
    TO_DATE(p.fecha_trabajo, 'DD/MM/YY') AS fecha_completa,
    EXTRACT(DOW FROM TO_DATE(p.fecha_trabajo, 'DD/MM/YY')) AS dia_semana,
    CASE 
        WHEN EXTRACT(DOW FROM TO_DATE(p.fecha_trabajo, 'DD/MM/YY')) = 0 THEN 'Domingo'
        WHEN EXTRACT(DOW FROM TO_DATE(p.fecha_trabajo, 'DD/MM/YY')) = 1 THEN 'Lunes'
        WHEN EXTRACT(DOW FROM TO_DATE(p.fecha_trabajo, 'DD/MM/YY')) = 2 THEN 'Martes'
        WHEN EXTRACT(DOW FROM TO_DATE(p.fecha_trabajo, 'DD/MM/YY')) = 3 THEN 'Miércoles'
        WHEN EXTRACT(DOW FROM TO_DATE(p.fecha_trabajo, 'DD/MM/YY')) = 4 THEN 'Jueves'
        WHEN EXTRACT(DOW FROM TO_DATE(p.fecha_trabajo, 'DD/MM/YY')) = 5 THEN 'Viernes'
        WHEN EXTRACT(DOW FROM TO_DATE(p.fecha_trabajo, 'DD/MM/YY')) = 6 THEN 'Sábado'
    END AS nombre_dia,
    COUNT(*) AS ordenes_completadas,
    SUM(calcular_minutos_hora_extra(
        p.fecha_trabajo,
        p.hora_inicio,
        p.hora_fin,
        p.duracion_min
    )) AS minutos_hora_extra,
    ROUND(SUM(calcular_minutos_hora_extra(
        p.fecha_trabajo,
        p.hora_inicio,
        p.hora_fin,
        p.duracion_min
    )) / 60.0, 2) AS horas_extra,
    MIN(p.hora_inicio) AS primera_orden,
    MAX(p.hora_fin) AS ultima_orden
FROM produccion p
WHERE p.estado = 'Completado'
  AND p.rut_tecnico IS NOT NULL
  AND p.rut_tecnico != ''
  AND p.rut_tecnico NOT LIKE '%-%-T%'
  AND LENGTH(p.rut_tecnico) BETWEEN 9 AND 12
GROUP BY p.rut_tecnico, p.tecnico, p.fecha_trabajo, fecha_completa, dia_semana
HAVING SUM(calcular_minutos_hora_extra(
    p.fecha_trabajo,
    p.hora_inicio,
    p.hora_fin,
    p.duracion_min
)) > 0
ORDER BY fecha_completa DESC, p.rut_tecnico;

-- ═════════════════════════════════════════════════════════════════
-- PASO 6: VISTA DE HORAS EXTRAS ACUMULADAS POR MES
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW v_horas_extras_mensuales AS
SELECT
    rut_tecnico,
    tecnico,
    EXTRACT(MONTH FROM fecha_completa) AS mes,
    EXTRACT(YEAR FROM fecha_completa) AS anio,
    COUNT(DISTINCT fecha_trabajo) AS dias_con_hora_extra,
    SUM(minutos_hora_extra) AS minutos_hora_extra_total,
    ROUND(SUM(minutos_hora_extra) / 60.0, 2) AS horas_extra_total,
    MIN(fecha_completa) AS primera_fecha,
    MAX(fecha_completa) AS ultima_fecha
FROM v_horas_extras_diarias
GROUP BY rut_tecnico, tecnico, mes, anio
ORDER BY anio DESC, mes DESC, horas_extra_total DESC;

-- ═════════════════════════════════════════════════════════════════
-- PRUEBAS DE VERIFICACIÓN
-- ═════════════════════════════════════════════════════════════════

-- Prueba 1: Ver horas extras de Alberto Escalona en Enero 2026
SELECT * FROM v_horas_extras_diarias
WHERE rut_tecnico = '26402839-6'
  AND EXTRACT(MONTH FROM fecha_completa) = 1
  AND EXTRACT(YEAR FROM fecha_completa) = 2026
ORDER BY fecha_completa;

-- Prueba 2: Resumen mensual de horas extras de Alberto
SELECT * FROM v_horas_extras_mensuales
WHERE rut_tecnico = '26402839-6'
  AND mes = 1
  AND anio = 2026;

-- Prueba 3: Top 10 técnicos con más horas extras en Enero 2026
SELECT * FROM v_horas_extras_mensuales
WHERE mes = 1 AND anio = 2026
ORDER BY horas_extra_total DESC
LIMIT 10;

-- Prueba 4: Validar cálculo manual para una orden específica de Alberto
-- (05/01/26, última orden a las 20:15, terminó después de las 18:30)
SELECT 
    orden_trabajo,
    fecha_trabajo,
    hora_inicio,
    hora_fin,
    duracion_min,
    calcular_minutos_hora_extra(fecha_trabajo, hora_inicio, hora_fin, duracion_min) AS minutos_extra_calculados
FROM produccion
WHERE rut_tecnico = '26402839-6'
  AND fecha_trabajo = '05/01/26'
  AND hora_fin IS NOT NULL
ORDER BY hora_fin DESC;

