-- ═══════════════════════════════════════════════════════════════════
-- 🔧 FIX: Recrear tablas TRAZA con estructura correcta
-- ═══════════════════════════════════════════════════════════════════
-- Este script elimina las tablas existentes y las recrea correctamente
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- PASO 1: Eliminar tablas existentes (si existen)
-- ═══════════════════════════════════════════════════════════════════

DROP TABLE IF EXISTS pagos_traza CASCADE;
DROP TABLE IF EXISTS calidad_traza CASCADE;
DROP TABLE IF EXISTS produccion_traza CASCADE;
DROP TABLE IF EXISTS escala_hfc CASCADE;
DROP TABLE IF EXISTS escala_ntt CASCADE;
DROP TABLE IF EXISTS escala_ftth CASCADE;
DROP TABLE IF EXISTS tipos_orden CASCADE;

DROP VIEW IF EXISTS v_pagos_traza CASCADE;

SELECT '✅ Tablas antiguas eliminadas' AS estado;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 2: Crear tabla de tipos de orden
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE tipos_orden (
    id SERIAL PRIMARY KEY,
    codigo VARCHAR(50) UNIQUE NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    puntos_rgu NUMERIC(3,2) NOT NULL,
    tecnologia VARCHAR(20),
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO tipos_orden (codigo, nombre, puntos_rgu, tecnologia) VALUES
('1_PLAY', '1 Play', 1.00, 'FTTH'),
('2_PLAY', '2 Play', 2.00, 'FTTH'),
('3_PLAY', '3 Play', 3.00, 'FTTH'),
('MODIFICACION', 'Modificación', 0.75, 'FTTH'),
('EXTENSOR', 'Extensor Adicional', 0.75, 'FTTH'),
('DECODIFICADOR', 'Decodificador Adicional', 0.50, 'FTTH');

SELECT '✅ Tabla tipos_orden creada' AS estado;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 3: Crear tabla escala_ftth con TODAS las columnas
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE escala_ftth (
    id SERIAL PRIMARY KEY,
    rgu_desde NUMERIC(5,1) NOT NULL,
    rgu_hasta NUMERIC(5,1) NOT NULL,
    calidad_0_pct INTEGER,
    calidad_8_pct INTEGER,
    calidad_9_pct INTEGER,
    calidad_10_pct INTEGER,
    calidad_11_pct INTEGER,
    calidad_12_pct INTEGER,
    calidad_13_pct INTEGER,
    calidad_14_pct INTEGER,
    calidad_15_pct INTEGER,
    calidad_16_pct INTEGER,
    calidad_17_pct INTEGER,
    calidad_12_5_pct INTEGER,
    created_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT uq_escala_ftth_rango UNIQUE(rgu_desde, rgu_hasta)
);

SELECT '✅ Tabla escala_ftth creada' AS estado;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 4: Insertar datos FTTH (27 filas)
-- ═══════════════════════════════════════════════════════════════════

INSERT INTO escala_ftth (rgu_desde, rgu_hasta, calidad_0_pct, calidad_8_pct, calidad_9_pct, calidad_10_pct, calidad_11_pct, calidad_12_pct, calidad_13_pct, calidad_14_pct, calidad_15_pct, calidad_16_pct, calidad_17_pct, calidad_12_5_pct) VALUES
(0.0, 52.9, 3300, 3250, 3150, 2950, 2700, 2200, 800, 800, 800, 800, 800, 800),
(52.9, 57.3, 4300, 4250, 4150, 3950, 3700, 3200, 2700, 800, 800, 800, 800, 800),
(57.4, 61.9, 5300, 5250, 5150, 4950, 4700, 4200, 3700, 3200, 800, 800, 800, 800),
(61.9, 66.3, 6300, 6250, 6150, 5950, 5700, 5200, 4700, 4200, 800, 800, 800, 800),
(66.4, 70.9, 7300, 7250, 7150, 6950, 6700, 6200, 5700, 5200, 4700, 4200, 2000, 2000),
(70.9, 75.3, 7500, 7450, 7350, 7150, 6900, 6400, 5900, 5400, 4900, 4400, 2000, 2000),
(75.4, 79.8, 7700, 7650, 7550, 7350, 7100, 6600, 6100, 5600, 5100, 4600, 2000, 2000),
(79.9, 84.4, 7900, 7750, 7650, 7450, 7200, 6700, 6200, 5700, 5200, 4700, 2000, 2000),
(84.4, 88.8, 7900, 7850, 7750, 7550, 7300, 6800, 6300, 5800, 5300, 4800, 2000, 2000),
(88.9, 93.5, 8000, 7950, 7850, 7650, 7400, 6900, 6400, 5900, 5400, 4900, 2000, 2000),
(93.6, 98.0, 8100, 8050, 7950, 7750, 7500, 7000, 6500, 6000, 5500, 5000, 2000, 2000),
(98.0, 102.5, 8200, 8150, 8050, 7850, 7600, 7100, 6600, 6100, 5600, 5100, 2000, 2000),
(102.5, 107.0, 8300, 8250, 8150, 7950, 7700, 7200, 6700, 6200, 5700, 5200, 2000, 2000),
(107.0, 111.5, 8400, 8350, 8250, 8050, 7800, 7300, 6800, 6300, 5800, 5300, 2000, 2000),
(111.5, 116.0, 8500, 8450, 8350, 8150, 7900, 7400, 6900, 6400, 5900, 5400, 2000, 2000),
(116.0, 120.5, 8600, 8550, 8450, 8250, 8000, 7500, 7000, 6500, 6000, 5500, 2000, 2000),
(120.5, 125.0, 8700, 8650, 8550, 8350, 8100, 7600, 7100, 6600, 6100, 5600, 2000, 2000),
(125.0, 129.5, 8800, 8750, 8650, 8450, 8200, 7700, 7200, 6700, 6200, 5700, 2000, 2000),
(129.5, 134.0, 8900, 8850, 8750, 8550, 8300, 7800, 7300, 6800, 6300, 5800, 2000, 2000),
(134.0, 138.6, 9000, 8950, 8850, 8650, 8400, 7900, 7400, 6900, 6400, 5900, 2000, 2000),
(138.6, 143.1, 9100, 9050, 8950, 8750, 8500, 8000, 7500, 7000, 6500, 6000, 2000, 2000),
(143.1, 147.6, 9200, 9150, 9050, 8850, 8600, 8100, 7600, 7100, 6600, 6100, 2000, 2000),
(147.6, 152.1, 9300, 9250, 9150, 8950, 8700, 8200, 7700, 7200, 6700, 6200, 2000, 2000),
(152.1, 156.6, 9400, 9350, 9250, 9050, 8800, 8300, 7800, 7300, 6800, 6300, 2000, 2000),
(156.6, 161.1, 9500, 9450, 9350, 9150, 8900, 8400, 7900, 7400, 6900, 6400, 2000, 2000),
(161.1, 165.6, 9600, 9550, 9450, 9250, 9000, 8500, 8000, 7500, 7000, 6500, 2000, 2000),
(165.6, 999.9, 9700, 9650, 9550, 9350, 9100, 8600, 8100, 7600, 7100, 6600, 2000, 2000);

SELECT '✅ Datos FTTH insertados (27 filas)' AS estado;
SELECT COUNT(*) AS total_filas_ftth FROM escala_ftth;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 5: Crear tabla escala_ntt
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE escala_ntt (
    id SERIAL PRIMARY KEY,
    actividades_desde INTEGER NOT NULL,
    actividades_hasta INTEGER NOT NULL,
    calidad_0_pct INTEGER,
    calidad_9_pct INTEGER,
    calidad_11_pct INTEGER,
    calidad_13_pct INTEGER,
    calidad_15_pct INTEGER,
    calidad_17_pct INTEGER,
    calidad_19_pct INTEGER,
    calidad_21_pct INTEGER,
    calidad_23_pct INTEGER,
    created_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT uq_escala_ntt_rango UNIQUE(actividades_desde, actividades_hasta)
);

SELECT '✅ Tabla escala_ntt creada' AS estado;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 6: Insertar datos NTT (29 filas)
-- ═══════════════════════════════════════════════════════════════════

INSERT INTO escala_ntt (actividades_desde, actividades_hasta, calidad_0_pct, calidad_9_pct, calidad_11_pct, calidad_13_pct, calidad_15_pct, calidad_17_pct, calidad_19_pct, calidad_21_pct, calidad_23_pct) VALUES
(57, 62, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(62, 67, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(67, 72, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(72, 77, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(77, 82, 950, 950, 800, 650, 500, 150, 100, 50, NULL),
(82, 87, 1450, 1450, 1300, 1150, 1000, 450, 300, 150, NULL),
(87, 92, 2450, 2450, 2300, 2150, 2000, 1550, 400, 200, NULL),
(92, 97, 3650, 3650, 3500, 3350, 3200, 1700, 700, 200, NULL),
(97, 102, 4150, 4150, 4000, 3850, 3700, 2200, 1200, 200, NULL),
(102, 107, 4750, 4750, 4600, 4450, 4300, 2800, 1800, 800, NULL),
(107, 111, 4800, 4800, 4650, 4500, 4350, 2850, 1850, 850, 650),
(111, 116, 4850, 4850, 4700, 4550, 4400, 2900, 1900, 900, 700),
(116, 121, 4900, 4900, 4750, 4600, 4450, 2950, 1950, 950, 750),
(121, 126, 4950, 4950, 4800, 4650, 4500, 3000, 2000, 1000, 800),
(126, 131, 5000, 5000, 4850, 4700, 4550, 3050, 2050, 1050, 850),
(131, 136, 5050, 5050, 4900, 4750, 4600, 3100, 2100, 1100, 900),
(136, 141, 5100, 5100, 4950, 4800, 4650, 3150, 2150, 1150, 950),
(141, 147, 5150, 5150, 5000, 4850, 4700, 3200, 2200, 1200, 1000),
(147, 152, 5200, 5200, 5050, 4900, 4750, 3250, 2250, 1250, 1050),
(152, 157, 5250, 5250, 5100, 4950, 4800, 3300, 2300, 1300, 1100),
(157, 162, 5300, 5300, 5150, 5000, 4850, 3350, 2350, 1350, 1150),
(162, 167, 5350, 5350, 5200, 5050, 4900, 3400, 2400, 1400, 1200),
(167, 172, 5400, 5400, 5250, 5100, 4950, 3450, 2450, 1450, 1250),
(172, 177, 5450, 5450, 5300, 5150, 5000, 3500, 2500, 1500, 1300),
(177, 182, 5500, 5500, 5350, 5200, 5050, 3550, 2550, 1550, 1350),
(182, 187, 5550, 5550, 5400, 5250, 5100, 3600, 2600, 1600, 1400),
(187, 193, 5600, 5600, 5450, 5300, 5150, 3650, 2650, 1650, 1450),
(193, 197, 5650, 5650, 5500, 5350, 5200, 3700, 2700, 1700, 1500),
(197, 999, 5650, 5650, 5500, 5350, 5200, 3700, 2700, 1700, 1500);

SELECT '✅ Datos NTT insertados (29 filas)' AS estado;
SELECT COUNT(*) AS total_filas_ntt FROM escala_ntt;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 7: Crear tablas de producción, calidad y pagos
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE produccion_traza (
    id SERIAL PRIMARY KEY,
    rut_tecnico VARCHAR(12) NOT NULL,
    tecnico VARCHAR(255),
    fecha_trabajo VARCHAR(20) NOT NULL,
    orden_trabajo VARCHAR(50),
    tipo_orden VARCHAR(50),
    tecnologia VARCHAR(20),
    puntos_rgu NUMERIC(3,2),
    estado VARCHAR(50),
    cliente VARCHAR(255),
    direccion TEXT,
    comuna VARCHAR(100),
    region VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_produccion_traza_rut ON produccion_traza(rut_tecnico);
CREATE INDEX idx_produccion_traza_fecha ON produccion_traza(fecha_trabajo);
CREATE INDEX idx_produccion_traza_tecnologia ON produccion_traza(tecnologia);

CREATE TABLE calidad_traza (
    id SERIAL PRIMARY KEY,
    rut_tecnico VARCHAR(12) NOT NULL,
    tecnico VARCHAR(255),
    orden_original VARCHAR(50),
    fecha_original VARCHAR(20),
    orden_reiterada VARCHAR(50),
    fecha_reiterada VARCHAR(20),
    tecnologia VARCHAR(20),
    descripcion_reiterado TEXT,
    responsabilidad VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_calidad_traza_rut ON calidad_traza(rut_tecnico);
CREATE INDEX idx_calidad_traza_tecnologia ON calidad_traza(tecnologia);

CREATE TABLE pagos_traza (
    id SERIAL PRIMARY KEY,
    rut_tecnico VARCHAR(12) NOT NULL,
    tecnico VARCHAR(255),
    periodo VARCHAR(7) NOT NULL,
    tecnologia VARCHAR(20),
    rgu_total NUMERIC(6,1),
    actividades_total INTEGER,
    puntos_total INTEGER,
    ordenes_completadas INTEGER,
    ordenes_reiteradas INTEGER,
    porcentaje_calidad NUMERIC(5,2),
    monto_bono INTEGER,
    fecha_calculo TIMESTAMP DEFAULT NOW(),
    calculado_por VARCHAR(50) DEFAULT 'sistema',
    CONSTRAINT uq_pago_traza_periodo UNIQUE(rut_tecnico, periodo, tecnologia)
);

CREATE INDEX idx_pagos_traza_rut ON pagos_traza(rut_tecnico);
CREATE INDEX idx_pagos_traza_periodo ON pagos_traza(periodo);
CREATE INDEX idx_pagos_traza_tecnologia ON pagos_traza(tecnologia);

SELECT '✅ Tablas de producción, calidad y pagos creadas' AS estado;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 8: Crear funciones
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION obtener_puntos_rgu(p_tipo_orden VARCHAR)
RETURNS NUMERIC AS $$
DECLARE
    v_puntos NUMERIC;
BEGIN
    SELECT puntos_rgu INTO v_puntos
    FROM tipos_orden
    WHERE codigo = p_tipo_orden;
    RETURN COALESCE(v_puntos, 0);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION obtener_bono_ftth(
    p_rgu_total NUMERIC,
    p_porcentaje_calidad NUMERIC
)
RETURNS INTEGER AS $$
DECLARE
    v_monto INTEGER := 0;
    v_columna_calidad VARCHAR;
BEGIN
    IF p_porcentaje_calidad >= 100 THEN
        v_columna_calidad := 'calidad_0_pct';
    ELSIF p_porcentaje_calidad >= 92 THEN
        v_columna_calidad := 'calidad_8_pct';
    ELSIF p_porcentaje_calidad >= 91 THEN
        v_columna_calidad := 'calidad_9_pct';
    ELSIF p_porcentaje_calidad >= 90 THEN
        v_columna_calidad := 'calidad_10_pct';
    ELSIF p_porcentaje_calidad >= 89 THEN
        v_columna_calidad := 'calidad_11_pct';
    ELSIF p_porcentaje_calidad >= 88 THEN
        v_columna_calidad := 'calidad_12_pct';
    ELSIF p_porcentaje_calidad >= 87 THEN
        v_columna_calidad := 'calidad_13_pct';
    ELSIF p_porcentaje_calidad >= 86 THEN
        v_columna_calidad := 'calidad_14_pct';
    ELSIF p_porcentaje_calidad >= 85 THEN
        v_columna_calidad := 'calidad_15_pct';
    ELSIF p_porcentaje_calidad >= 84 THEN
        v_columna_calidad := 'calidad_16_pct';
    ELSIF p_porcentaje_calidad >= 83 THEN
        v_columna_calidad := 'calidad_17_pct';
    ELSE
        v_columna_calidad := 'calidad_12_5_pct';
    END IF;
    
    EXECUTE format('
        SELECT %I FROM escala_ftth
        WHERE $1 >= rgu_desde AND $1 <= rgu_hasta
        LIMIT 1
    ', v_columna_calidad)
    INTO v_monto
    USING p_rgu_total;
    
    RETURN COALESCE(v_monto, 0);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION obtener_bono_ntt(
    p_actividades_total INTEGER,
    p_porcentaje_calidad NUMERIC
)
RETURNS INTEGER AS $$
DECLARE
    v_monto INTEGER := 0;
    v_columna_calidad VARCHAR;
BEGIN
    IF p_porcentaje_calidad >= 100 THEN
        v_columna_calidad := 'calidad_0_pct';
    ELSIF p_porcentaje_calidad >= 91 THEN
        v_columna_calidad := 'calidad_9_pct';
    ELSIF p_porcentaje_calidad >= 89 THEN
        v_columna_calidad := 'calidad_11_pct';
    ELSIF p_porcentaje_calidad >= 87 THEN
        v_columna_calidad := 'calidad_13_pct';
    ELSIF p_porcentaje_calidad >= 85 THEN
        v_columna_calidad := 'calidad_15_pct';
    ELSIF p_porcentaje_calidad >= 83 THEN
        v_columna_calidad := 'calidad_17_pct';
    ELSIF p_porcentaje_calidad >= 81 THEN
        v_columna_calidad := 'calidad_19_pct';
    ELSIF p_porcentaje_calidad >= 79 THEN
        v_columna_calidad := 'calidad_21_pct';
    ELSIF p_porcentaje_calidad >= 77 THEN
        v_columna_calidad := 'calidad_23_pct';
    ELSE
        RETURN 0;
    END IF;
    
    EXECUTE format('
        SELECT %I FROM escala_ntt
        WHERE $1 >= actividades_desde AND $1 <= actividades_hasta
        LIMIT 1
    ', v_columna_calidad)
    INTO v_monto
    USING p_actividades_total;
    
    RETURN COALESCE(v_monto, 0);
END;
$$ LANGUAGE plpgsql;

SELECT '✅ Funciones creadas' AS estado;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 9: Crear vista
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW v_pagos_traza AS
SELECT 
    p.id,
    p.rut_tecnico,
    p.tecnico,
    p.periodo,
    p.tecnologia,
    p.rgu_total,
    p.actividades_total,
    p.puntos_total,
    p.ordenes_completadas,
    p.ordenes_reiteradas,
    p.porcentaje_calidad,
    ROUND((p.ordenes_reiteradas::NUMERIC / NULLIF(p.ordenes_completadas, 0)) * 100, 2) AS porcentaje_reiteracion,
    p.monto_bono,
    p.fecha_calculo,
    EXTRACT(YEAR FROM TO_DATE(p.periodo || '-01', 'YYYY-MM-DD')) AS anio,
    EXTRACT(MONTH FROM TO_DATE(p.periodo || '-01', 'YYYY-MM-DD')) AS mes
FROM pagos_traza p
ORDER BY p.periodo DESC, p.monto_bono DESC;

SELECT '✅ Vista v_pagos_traza creada' AS estado;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 10: Verificar instalación
-- ═══════════════════════════════════════════════════════════════════

SELECT '🎉 INSTALACIÓN COMPLETADA' AS estado;
SELECT '' AS separador;

SELECT '📊 Resumen:' AS titulo;
SELECT 'Tipos de orden' AS tabla, COUNT(*) AS registros FROM tipos_orden
UNION ALL
SELECT 'Escala FTTH' AS tabla, COUNT(*) AS registros FROM escala_ftth
UNION ALL
SELECT 'Escala NTT' AS tabla, COUNT(*) AS registros FROM escala_ntt;

SELECT '' AS separador;
SELECT '🧪 Pruebas de funciones:' AS titulo;

SELECT 'Bono FTTH (60 RGU, 92% cal)' AS test, obtener_bono_ftth(60.0, 92.0) AS resultado_esperado_4250;
SELECT 'Bono NTT (100 act, 90% cal)' AS test, obtener_bono_ntt(100, 90.0) AS resultado_esperado_4000;

SELECT '✅ Sistema listo para usar' AS estado_final;

