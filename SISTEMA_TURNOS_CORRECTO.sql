-- ═══════════════════════════════════════════════════════════════════
-- SISTEMA DE CÁLCULO DE DÍAS OPERATIVOS Y TURNOS - VERSIÓN CORRECTA
-- ═══════════════════════════════════════════════════════════════════
-- Turno 5x2: Días mes - (2 × Domingos) - Festivos
-- Turno 6x1: Días mes - Domingos - Festivos
-- ═══════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════
-- PASO 1: Agregar columna tipo_turno a tecnicos_traza_zc
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE tecnicos_traza_zc 
ADD COLUMN IF NOT EXISTS tipo_turno VARCHAR(3) DEFAULT '5x2';

UPDATE tecnicos_traza_zc 
SET tipo_turno = '5x2'
WHERE tipo_turno IS NULL OR tipo_turno = '';

-- ══════════════════════════════════════════════════════════════════
-- PASO 2: Tabla de festivos Chile 2026
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS festivos_chile (
    id SERIAL PRIMARY KEY,
    fecha DATE NOT NULL UNIQUE,
    nombre VARCHAR(100) NOT NULL,
    tipo VARCHAR(20) DEFAULT 'nacional',
    created_at TIMESTAMP DEFAULT NOW()
);

TRUNCATE TABLE festivos_chile;

INSERT INTO festivos_chile (fecha, nombre, tipo) VALUES
('2026-01-01', 'Año Nuevo', 'nacional'),
('2026-04-03', 'Viernes Santo', 'religioso'),
('2026-04-04', 'Sábado Santo', 'religioso'),
('2026-05-01', 'Día del Trabajador', 'nacional'),
('2026-05-21', 'Glorias Navales', 'nacional'),
('2026-06-29', 'San Pedro y San Pablo', 'religioso'),
('2026-07-16', 'Día de la Virgen del Carmen', 'religioso'),
('2026-08-15', 'Asunción de la Virgen', 'religioso'),
('2026-09-18', 'Independencia Nacional', 'nacional'),
('2026-09-19', 'Día de las Glorias del Ejército', 'nacional'),
('2026-10-12', 'Encuentro de Dos Mundos', 'nacional'),
('2026-10-31', 'Día de las Iglesias Evangélicas', 'religioso'),
('2026-11-01', 'Día de Todos los Santos', 'religioso'),
('2026-12-08', 'Inmaculada Concepción', 'religioso'),
('2026-12-25', 'Navidad', 'religioso');

-- ══════════════════════════════════════════════════════════════════
-- PASO 3: Función para calcular días operativos según turno
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calcular_dias_operativos(
    p_mes INTEGER,
    p_anio INTEGER,
    p_tipo_turno VARCHAR DEFAULT '5x2'
)
RETURNS INTEGER AS $$
DECLARE
    v_primer_dia DATE;
    v_ultimo_dia DATE;
    v_dia_actual DATE;
    v_dias_mes INTEGER;
    v_domingos INTEGER := 0;
    v_festivos INTEGER := 0;
    v_dias_operativos INTEGER;
    v_dow INTEGER;
BEGIN
    -- Calcular primer y último día del mes
    v_primer_dia := make_date(p_anio, p_mes, 1);
    v_ultimo_dia := (v_primer_dia + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
    v_dias_mes := EXTRACT(DAY FROM v_ultimo_dia);
    
    -- Contar domingos y festivos
    v_dia_actual := v_primer_dia;
    
    WHILE v_dia_actual <= v_ultimo_dia LOOP
        v_dow := EXTRACT(DOW FROM v_dia_actual); -- 0=Domingo
        
        -- Contar domingos
        IF v_dow = 0 THEN
            v_domingos := v_domingos + 1;
        END IF;
        
        -- Contar festivos (que no sean domingo)
        IF EXISTS (SELECT 1 FROM festivos_chile WHERE fecha = v_dia_actual) AND v_dow != 0 THEN
            v_festivos := v_festivos + 1;
        END IF;
        
        v_dia_actual := v_dia_actual + INTERVAL '1 day';
    END LOOP;
    
    -- Calcular días operativos según tipo de turno
    IF UPPER(p_tipo_turno) = '5X2' THEN
        -- Turno 5x2: Por cada domingo se descansan 2 días
        v_dias_operativos := v_dias_mes - (2 * v_domingos) - v_festivos;
    ELSIF UPPER(p_tipo_turno) = '6X1' THEN
        -- Turno 6x1: Solo se descansa domingo
        v_dias_operativos := v_dias_mes - v_domingos - v_festivos;
    ELSE
        -- Por defecto, usar 5x2
        v_dias_operativos := v_dias_mes - (2 * v_domingos) - v_festivos;
    END IF;
    
    RETURN v_dias_operativos;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calcular_dias_operativos IS 'Calcula días operativos: 5x2 = mes - (2×domingos) - festivos | 6x1 = mes - domingos - festivos';

-- ══════════════════════════════════════════════════════════════════
-- PASO 4: Vista para ranking de producción
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW v_ranking_produccion AS
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

COMMENT ON VIEW v_ranking_produccion IS 'Ranking por promedio RGU/día operativo';

-- ══════════════════════════════════════════════════════════════════
-- PASO 5: PRUEBAS DE VERIFICACIÓN
-- ══════════════════════════════════════════════════════════════════

-- Prueba 1: Enero 2026 turno 5x2 (debe dar 20)
SELECT 
    'Enero 2026 (5x2)' as periodo,
    calcular_dias_operativos(1, 2026, '5x2') as dias_operativos,
    '20 esperado (31 - 10 - 1)' as calculo;

-- Prueba 2: Febrero 2026 turno 5x2 (debe dar 20)
SELECT 
    'Febrero 2026 (5x2)' as periodo,
    calcular_dias_operativos(2, 2026, '5x2') as dias_operativos,
    '20 esperado (28 - 8 - 0)' as calculo;

-- Prueba 3: Enero 2026 turno 6x1 (debe dar 25)
SELECT 
    'Enero 2026 (6x1)' as periodo,
    calcular_dias_operativos(1, 2026, '6x1') as dias_operativos,
    '25 esperado (31 - 5 - 1)' as calculo;

-- Prueba 4: Febrero 2026 turno 6x1 (debe dar 24)
SELECT 
    'Febrero 2026 (6x1)' as periodo,
    calcular_dias_operativos(2, 2026, '6x1') as dias_operativos,
    '24 esperado (28 - 4 - 0)' as calculo;

-- Prueba 5: Ver ranking Enero 2026
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
WHERE mes = 1 AND anio = 2026
ORDER BY ranking
LIMIT 10;

-- Prueba 6: Ver ranking Febrero 2026
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
WHERE mes = 2 AND anio = 2026
ORDER BY ranking
LIMIT 10;

-- ══════════════════════════════════════════════════════════════════
-- RESUMEN DE CÁLCULOS
-- ══════════════════════════════════════════════════════════════════

/*
FÓRMULAS:
---------
Turno 5x2: Días Operativos = Días mes - (2 × Domingos) - Festivos
Turno 6x1: Días Operativos = Días mes - Domingos - Festivos

RESULTADOS ESPERADOS 2026:
---------------------------
Enero (5x2):   31 - (2×5) - 1 = 20 días
Enero (6x1):   31 - 5 - 1 = 25 días
Febrero (5x2): 28 - (2×4) - 0 = 20 días
Febrero (6x1): 28 - 4 - 0 = 24 días

LÓGICA:
-------
5x2 = Trabajan 5 días, descansan 2 días
      Por cada domingo, hay 1 día adicional de descanso
      Por eso se multiplica: 2 × domingos

6x1 = Trabajan 6 días, descansan 1 día (domingo)
      Solo se descuenta el domingo

PRÓXIMOS PASOS:
---------------
1. Ejecutar este SQL en Supabase
2. Verificar que las pruebas den los resultados esperados
3. Actualizar la app Flutter (produccion_service.dart)
4. Actualizar el ranking en ProduccionScreen
*/

