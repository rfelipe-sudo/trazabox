-- ═══════════════════════════════════════════════════════════════════
-- PRUEBA DEL SISTEMA DE HORAS EXTRAS CON ALBERTO ESCALONA G
-- ═══════════════════════════════════════════════════════════════════

-- =====================================================================
-- PRUEBA 1: Verificar cálculo manual del 05/01/26
-- =====================================================================
-- Alberto trabajó hasta las 20:15, después de las 18:30 (hora límite)
-- Esperamos ver minutos de hora extra en las órdenes después de 18:30

SELECT 
    '🔍 DETALLE 05/01/26 - Alberto Escalona' AS titulo,
    orden_trabajo,
    hora_inicio,
    hora_fin,
    duracion_min,
    calcular_minutos_hora_extra(
        fecha_trabajo,
        hora_inicio,
        hora_fin,
        duracion_min
    ) AS minutos_extra,
    CASE 
        WHEN hora_fin::TIME > '18:30'::TIME THEN '✅ Después de 18:30'
        ELSE '❌ Antes de 18:30'
    END AS clasificacion
FROM produccion
WHERE rut_tecnico = '26402839-6'
  AND fecha_trabajo = '05/01/26'
  AND hora_fin IS NOT NULL
ORDER BY hora_fin;

-- =====================================================================
-- PRUEBA 2: Resumen diario de horas extras de Alberto en Enero
-- =====================================================================

SELECT 
    '📊 RESUMEN DIARIO ENERO - Alberto Escalona' AS titulo,
    fecha_trabajo,
    nombre_dia,
    ordenes_completadas,
    primera_orden,
    ultima_orden,
    minutos_hora_extra,
    horas_extra,
    CASE 
        WHEN nombre_dia = 'Domingo' THEN '🌙 Domingo (todo es hora extra)'
        WHEN nombre_dia = 'Sábado' THEN '📅 Sábado (después de 14:00)'
        ELSE '📝 L-V (después de 18:30)'
    END AS tipo_dia
FROM v_horas_extras_diarias
WHERE rut_tecnico = '26402839-6'
  AND EXTRACT(MONTH FROM fecha_completa) = 1
  AND EXTRACT(YEAR FROM fecha_completa) = 2026
ORDER BY fecha_completa;

-- =====================================================================
-- PRUEBA 3: Resumen mensual de Alberto
-- =====================================================================

SELECT 
    '📈 RESUMEN MENSUAL ENERO - Alberto Escalona' AS titulo,
    dias_con_hora_extra AS dias_con_HE,
    minutos_hora_extra_total AS minutos_totales,
    horas_extra_total AS horas_totales,
    primera_fecha,
    ultima_fecha
FROM v_horas_extras_mensuales
WHERE rut_tecnico = '26402839-6'
  AND mes = 1
  AND anio = 2026;

-- =====================================================================
-- PRUEBA 4: Comparar con otros técnicos - Top 10 Enero 2026
-- =====================================================================

SELECT 
    '🏆 TOP 10 TÉCNICOS CON MÁS HORAS EXTRAS - ENERO 2026' AS titulo,
    ROW_NUMBER() OVER (ORDER BY horas_extra_total DESC) AS posicion,
    tecnico,
    dias_con_hora_extra,
    ROUND(horas_extra_total, 2) AS horas_extra,
    CASE 
        WHEN rut_tecnico = '26402839-6' THEN '👈 Alberto Escalona'
        ELSE ''
    END AS destacado
FROM v_horas_extras_mensuales
WHERE mes = 1 AND anio = 2026
ORDER BY horas_extra_total DESC
LIMIT 10;

-- =====================================================================
-- PRUEBA 5: Verificar días específicos (sábados y domingos)
-- =====================================================================

SELECT 
    '🗓️ TRABAJO EN FINES DE SEMANA - Alberto Escalona' AS titulo,
    fecha_trabajo,
    nombre_dia,
    ordenes_completadas,
    primera_orden,
    ultima_orden,
    horas_extra,
    CASE 
        WHEN nombre_dia = 'Sábado' AND ultima_orden::TIME > '14:00'::TIME 
            THEN '✅ Hora extra después de 14:00'
        WHEN nombre_dia = 'Domingo' 
            THEN '✅ Todo el día es hora extra'
        ELSE '❓ Verificar'
    END AS validacion
FROM v_horas_extras_diarias
WHERE rut_tecnico = '26402839-6'
  AND (nombre_dia = 'Sábado' OR nombre_dia = 'Domingo')
  AND EXTRACT(MONTH FROM fecha_completa) = 1
  AND EXTRACT(YEAR FROM fecha_completa) = 2026
ORDER BY fecha_completa;

-- =====================================================================
-- PRUEBA 6: Estadísticas generales de horas extras en Enero
-- =====================================================================

SELECT 
    '📊 ESTADÍSTICAS GENERALES ENERO 2026' AS titulo,
    COUNT(DISTINCT rut_tecnico) AS tecnicos_con_hora_extra,
    SUM(dias_con_hora_extra) AS total_dias_con_HE,
    ROUND(AVG(horas_extra_total), 2) AS promedio_horas_por_tecnico,
    ROUND(SUM(horas_extra_total), 2) AS total_horas_extra_empresa,
    MAX(horas_extra_total) AS max_horas_un_tecnico,
    MIN(horas_extra_total) AS min_horas_un_tecnico
FROM v_horas_extras_mensuales
WHERE mes = 1 AND anio = 2026;

-- =====================================================================
-- PRUEBA 7: Validar cálculo de festivos (01/01/26 = Año Nuevo)
-- =====================================================================

SELECT 
    '🎉 TRABAJO EN FESTIVOS - Alberto Escalona' AS titulo,
    fecha_trabajo,
    nombre_dia,
    ordenes_completadas,
    horas_extra,
    es_festivo(fecha_completa) AS es_festivo,
    CASE 
        WHEN es_festivo(fecha_completa) THEN '✅ Festivo detectado'
        WHEN nombre_dia = 'Domingo' THEN '✅ Domingo detectado'
        ELSE '📝 Día normal'
    END AS tipo
FROM v_horas_extras_diarias
WHERE rut_tecnico = '26402839-6'
  AND EXTRACT(MONTH FROM fecha_completa) = 1
  AND EXTRACT(YEAR FROM fecha_completa) = 2026
ORDER BY fecha_completa;

