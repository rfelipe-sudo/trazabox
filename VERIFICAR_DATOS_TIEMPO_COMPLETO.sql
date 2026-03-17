-- ═══════════════════════════════════════════════════════════════════
-- VERIFICAR DATOS DE TIEMPO Y HORAS EXTRAS EN PRODUCCION
-- ═══════════════════════════════════════════════════════════════════

-- 1️⃣ Resumen general de datos de tiempo en Enero 2026
SELECT 
    '🔍 RESUMEN GENERAL ENERO 2026' AS seccion,
    COUNT(*) AS total_registros,
    COUNT(hora_inicio) FILTER (WHERE hora_inicio IS NOT NULL AND hora_inicio != '') AS con_hora_inicio,
    COUNT(hora_fin) FILTER (WHERE hora_fin IS NOT NULL AND hora_fin != '') AS con_hora_fin,
    COUNT(duracion_min) FILTER (WHERE duracion_min IS NOT NULL AND duracion_min > 0) AS con_duracion,
    ROUND(
        COUNT(hora_inicio) FILTER (WHERE hora_inicio IS NOT NULL AND hora_inicio != '') * 100.0 / COUNT(*),
        2
    ) AS porcentaje_con_hora
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%');

-- 2️⃣ Ejemplos de registros CON datos de tiempo
SELECT 
    '📊 EJEMPLOS CON HORA' AS seccion,
    rut_tecnico,
    tecnico,
    fecha_trabajo,
    orden_trabajo,
    estado,
    hora_inicio,
    hora_fin,
    duracion_min,
    franja,
    marca
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND hora_inicio IS NOT NULL
  AND hora_inicio != ''
ORDER BY fecha_trabajo DESC, hora_inicio DESC
LIMIT 5;

-- 3️⃣ Ejemplos de registros SIN datos de tiempo
SELECT 
    '❌ EJEMPLOS SIN HORA' AS seccion,
    rut_tecnico,
    tecnico,
    fecha_trabajo,
    orden_trabajo,
    estado,
    hora_inicio,
    hora_fin,
    duracion_min
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND (hora_inicio IS NULL OR hora_inicio = '')
ORDER BY fecha_trabajo DESC
LIMIT 5;

-- 4️⃣ Análisis de la columna FRANJA (puede indicar horario extra)
SELECT 
    '⏰ ANÁLISIS DE FRANJAS' AS seccion,
    franja,
    COUNT(*) AS cantidad,
    ROUND(AVG(duracion_min), 2) AS duracion_promedio_min
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND franja IS NOT NULL
GROUP BY franja
ORDER BY cantidad DESC;

-- 5️⃣ Técnico específico: Alberto Escalona G (para debug)
SELECT 
    '👤 ALBERTO ESCALONA - DATOS DE TIEMPO' AS seccion,
    fecha_trabajo,
    orden_trabajo,
    estado,
    hora_inicio,
    hora_fin,
    duracion_min,
    franja,
    marca
FROM produccion
WHERE rut_tecnico = '26402839-6'
  AND (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
ORDER BY fecha_trabajo, hora_inicio
LIMIT 10;

-- 6️⃣ Distribución de horas de inicio (para detectar horario extra)
SELECT 
    '📅 DISTRIBUCIÓN DE HORAS DE INICIO' AS seccion,
    SUBSTRING(hora_inicio FROM 1 FOR 2) AS hora,
    COUNT(*) AS cantidad
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND hora_inicio IS NOT NULL
  AND hora_inicio != ''
GROUP BY SUBSTRING(hora_inicio FROM 1 FOR 2)
ORDER BY hora;

-- 7️⃣ Órdenes con más de 8 horas de duración (posibles horas extras)
SELECT 
    '⏳ ÓRDENES DE LARGA DURACIÓN (>480 min = 8h)' AS seccion,
    rut_tecnico,
    tecnico,
    fecha_trabajo,
    orden_trabajo,
    hora_inicio,
    hora_fin,
    duracion_min,
    ROUND(duracion_min / 60.0, 2) AS duracion_horas
FROM produccion
WHERE (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
  AND duracion_min > 480
ORDER BY duracion_min DESC
LIMIT 10;

