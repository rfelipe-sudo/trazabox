-- ═══════════════════════════════════════════════════════════════════
-- 📝 EJEMPLOS DE USO - SISTEMA DE BONOS TRAZA
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- EJEMPLO 1: Insertar órdenes de trabajo (FTTH)
-- ═══════════════════════════════════════════════════════════════════

-- Técnico Juan Pérez hace 3 órdenes en Diciembre 2025
INSERT INTO produccion_traza (rut_tecnico, tecnico, fecha_trabajo, orden_trabajo, tipo_orden, tecnologia, estado) VALUES
('12345678-9', 'Juan Pérez', '1/12/2025', 'OT-001', '2_PLAY', 'FTTH', 'Completado'),
('12345678-9', 'Juan Pérez', '2/12/2025', 'OT-002', '3_PLAY', 'FTTH', 'Completado'),
('12345678-9', 'Juan Pérez', '3/12/2025', 'OT-003', 'MODIFICACION', 'FTTH', 'Completado');

-- Actualizar puntos RGU automáticamente
UPDATE produccion_traza p
SET puntos_rgu = (SELECT puntos_rgu FROM tipos_orden WHERE codigo = p.tipo_orden)
WHERE puntos_rgu IS NULL;

-- Ver resultado
SELECT 
    tecnico,
    fecha_trabajo,
    tipo_orden,
    puntos_rgu,
    SUM(puntos_rgu) OVER (PARTITION BY rut_tecnico) AS rgu_total_mes
FROM produccion_traza
WHERE rut_tecnico = '12345678-9'
ORDER BY fecha_trabajo;

-- Resultado esperado:
-- OT-001: 2 play = 2.0 RGU
-- OT-002: 3 play = 3.0 RGU
-- OT-003: Modificación = 0.75 RGU
-- TOTAL: 5.75 RGU

-- ═══════════════════════════════════════════════════════════════════
-- EJEMPLO 2: Calcular bono FTTH
-- ═══════════════════════════════════════════════════════════════════

-- Caso 1: Técnico con 60 RGU y 92% calidad (8% reiteración)
SELECT 
    '📊 Caso 1: 60 RGU, 92% calidad' AS caso,
    60.0 AS rgu_total,
    92.0 AS porcentaje_calidad,
    8.0 AS porcentaje_reiteracion,
    obtener_bono_ftth(60.0, 92.0) AS bono_esperado;
-- Resultado esperado: $4,250

-- Caso 2: Técnico con 120 RGU y 100% calidad (0% reiteración)
SELECT 
    '📊 Caso 2: 120 RGU, 100% calidad' AS caso,
    120.0 AS rgu_total,
    100.0 AS porcentaje_calidad,
    0.0 AS porcentaje_reiteracion,
    obtener_bono_ftth(120.0, 100.0) AS bono_esperado;
-- Resultado esperado: $8,700

-- Caso 3: Técnico con 50 RGU y 85% calidad (15% reiteración)
SELECT 
    '📊 Caso 3: 50 RGU, 85% calidad' AS caso,
    50.0 AS rgu_total,
    85.0 AS porcentaje_calidad,
    15.0 AS porcentaje_reiteracion,
    obtener_bono_ftth(50.0, 85.0) AS bono_esperado;
-- Resultado esperado: $800

-- ═══════════════════════════════════════════════════════════════════
-- EJEMPLO 3: Calcular bono NTT
-- ═══════════════════════════════════════════════════════════════════

-- Caso 1: Técnico con 100 actividades y 90% calidad (10% reiteración)
SELECT 
    '📊 Caso 1: 100 act, 90% calidad' AS caso,
    100 AS actividades,
    90.0 AS porcentaje_calidad,
    10.0 AS porcentaje_reiteracion,
    obtener_bono_ntt(100, 90.0) AS bono_esperado;
-- Resultado esperado: $4,000

-- Caso 2: Técnico con 150 actividades y 95% calidad (5% reiteración)
SELECT 
    '📊 Caso 2: 150 act, 95% calidad' AS caso,
    150 AS actividades,
    95.0 AS porcentaje_calidad,
    5.0 AS porcentaje_reiteracion,
    obtener_bono_ntt(150, 95.0) AS bono_esperado;
-- Resultado esperado: $5,150

-- ═══════════════════════════════════════════════════════════════════
-- EJEMPLO 4: Calcular bono mensual completo
-- ═══════════════════════════════════════════════════════════════════

-- Paso 1: Calcular RGU total del técnico en el mes (FTTH)
WITH rgu_mensual AS (
    SELECT 
        rut_tecnico,
        tecnico,
        SUM(puntos_rgu) AS rgu_total,
        COUNT(*) AS ordenes_completadas
    FROM produccion_traza
    WHERE fecha_trabajo LIKE '%/12/2025' -- Diciembre 2025
      AND estado = 'Completado'
      AND tecnologia = 'FTTH'
    GROUP BY rut_tecnico, tecnico
),
-- Paso 2: Calcular reiteraciones
reiteraciones AS (
    SELECT 
        rut_tecnico,
        COUNT(*) AS ordenes_reiteradas
    FROM calidad_traza
    WHERE fecha_reiterada LIKE '%/12/2025'
      AND tecnologia = 'FTTH'
    GROUP BY rut_tecnico
),
-- Paso 3: Calcular % calidad
calidad_calculada AS (
    SELECT 
        r.rut_tecnico,
        r.tecnico,
        r.rgu_total,
        r.ordenes_completadas,
        COALESCE(re.ordenes_reiteradas, 0) AS ordenes_reiteradas,
        100 - ROUND((COALESCE(re.ordenes_reiteradas, 0)::NUMERIC / r.ordenes_completadas) * 100, 2) AS porcentaje_calidad
    FROM rgu_mensual r
    LEFT JOIN reiteraciones re ON r.rut_tecnico = re.rut_tecnico
)
-- Paso 4: Calcular bono
SELECT 
    rut_tecnico,
    tecnico,
    rgu_total,
    ordenes_completadas,
    ordenes_reiteradas,
    porcentaje_calidad,
    obtener_bono_ftth(rgu_total, porcentaje_calidad) AS monto_bono
FROM calidad_calculada
ORDER BY monto_bono DESC;

-- ═══════════════════════════════════════════════════════════════════
-- EJEMPLO 5: Guardar bonos calculados en tabla pagos_traza
-- ═══════════════════════════════════════════════════════════════════

-- Insertar bonos calculados (FTTH, Diciembre 2025)
WITH rgu_mensual AS (
    SELECT 
        rut_tecnico,
        tecnico,
        SUM(puntos_rgu) AS rgu_total,
        COUNT(*) AS ordenes_completadas
    FROM produccion_traza
    WHERE fecha_trabajo LIKE '%/12/2025'
      AND estado = 'Completado'
      AND tecnologia = 'FTTH'
    GROUP BY rut_tecnico, tecnico
),
reiteraciones AS (
    SELECT 
        rut_tecnico,
        COUNT(*) AS ordenes_reiteradas
    FROM calidad_traza
    WHERE fecha_reiterada LIKE '%/12/2025'
      AND tecnologia = 'FTTH'
    GROUP BY rut_tecnico
),
calidad_calculada AS (
    SELECT 
        r.rut_tecnico,
        r.tecnico,
        r.rgu_total,
        r.ordenes_completadas,
        COALESCE(re.ordenes_reiteradas, 0) AS ordenes_reiteradas,
        100 - ROUND((COALESCE(re.ordenes_reiteradas, 0)::NUMERIC / r.ordenes_completadas) * 100, 2) AS porcentaje_calidad
    FROM rgu_mensual r
    LEFT JOIN reiteraciones re ON r.rut_tecnico = re.rut_tecnico
)
INSERT INTO pagos_traza (
    rut_tecnico,
    tecnico,
    periodo,
    tecnologia,
    rgu_total,
    ordenes_completadas,
    ordenes_reiteradas,
    porcentaje_calidad,
    monto_bono
)
SELECT 
    rut_tecnico,
    tecnico,
    '2025-12' AS periodo,
    'FTTH' AS tecnologia,
    rgu_total,
    ordenes_completadas,
    ordenes_reiteradas,
    porcentaje_calidad,
    obtener_bono_ftth(rgu_total, porcentaje_calidad) AS monto_bono
FROM calidad_calculada
ON CONFLICT (rut_tecnico, periodo, tecnologia) 
DO UPDATE SET
    rgu_total = EXCLUDED.rgu_total,
    ordenes_completadas = EXCLUDED.ordenes_completadas,
    ordenes_reiteradas = EXCLUDED.ordenes_reiteradas,
    porcentaje_calidad = EXCLUDED.porcentaje_calidad,
    monto_bono = EXCLUDED.monto_bono,
    fecha_calculo = NOW();

-- Ver resultado
SELECT * FROM v_pagos_traza WHERE periodo = '2025-12' ORDER BY monto_bono DESC;

-- ═══════════════════════════════════════════════════════════════════
-- EJEMPLO 6: Consultas útiles
-- ═══════════════════════════════════════════════════════════════════

-- Top 10 técnicos FTTH del mes
SELECT 
    tecnico,
    rgu_total,
    porcentaje_calidad,
    monto_bono
FROM v_pagos_traza
WHERE periodo = '2025-12'
  AND tecnologia = 'FTTH'
ORDER BY monto_bono DESC
LIMIT 10;

-- Promedio de bono por tecnología
SELECT 
    tecnologia,
    COUNT(*) AS total_tecnicos,
    ROUND(AVG(rgu_total), 2) AS rgu_promedio,
    ROUND(AVG(porcentaje_calidad), 2) AS calidad_promedio,
    ROUND(AVG(monto_bono), 0) AS bono_promedio,
    SUM(monto_bono) AS total_bonos
FROM v_pagos_traza
WHERE periodo = '2025-12'
GROUP BY tecnologia;

-- Distribución de bonos por rango (FTTH)
SELECT 
    CASE 
        WHEN monto_bono < 3000 THEN '$0 - $3,000'
        WHEN monto_bono < 5000 THEN '$3,000 - $5,000'
        WHEN monto_bono < 7000 THEN '$5,000 - $7,000'
        WHEN monto_bono < 9000 THEN '$7,000 - $9,000'
        ELSE '$9,000+'
    END AS rango_bono,
    COUNT(*) AS cantidad_tecnicos,
    ROUND(AVG(rgu_total), 1) AS rgu_promedio,
    ROUND(AVG(porcentaje_calidad), 1) AS calidad_promedio
FROM v_pagos_traza
WHERE periodo = '2025-12'
  AND tecnologia = 'FTTH'
GROUP BY rango_bono
ORDER BY MIN(monto_bono);

