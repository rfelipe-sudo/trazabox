-- ═══════════════════════════════════════════════════════════════════
-- VERIFICAR DATOS REALES EN NUEVA BASE (szoywhtkilgvfrczuyqn)
-- ═══════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════
-- 1️⃣ VERIFICAR CANTIDAD DE REGISTROS
-- ══════════════════════════════════════════════════════════════════

SELECT COUNT(*) as total_registros FROM produccion;

-- ══════════════════════════════════════════════════════════════════
-- 2️⃣ VERIFICAR ESTRUCTURA DE LA TABLA
-- ══════════════════════════════════════════════════════════════════

SELECT 
    column_name, 
    data_type, 
    is_nullable
FROM information_schema.columns
WHERE table_name = 'produccion'
ORDER BY ordinal_position;

-- ══════════════════════════════════════════════════════════════════
-- 3️⃣ OBTENER TÉCNICOS DISPONIBLES PARA REGISTRO
-- ══════════════════════════════════════════════════════════════════

SELECT 
    rut_tecnico,
    tecnico,
    COUNT(*) as ordenes_completadas,
    ROUND(SUM(rgu_total)::numeric, 2) as rgu_total,
    MAX(fecha_trabajo) as ultima_actividad
FROM produccion
WHERE estado = 'Completado'
  AND fecha_trabajo LIKE '%/01/26%' -- Enero 2026
  AND rut_tecnico IS NOT NULL
  AND tecnico IS NOT NULL
GROUP BY rut_tecnico, tecnico
ORDER BY rgu_total DESC
LIMIT 10;

-- ══════════════════════════════════════════════════════════════════
-- 4️⃣ VER DATOS DE UN TÉCNICO ESPECÍFICO (EJEMPLO)
-- ══════════════════════════════════════════════════════════════════

-- Reemplaza '2026-01-06T08:00:00.000Z' con un RUT real de la consulta anterior
SELECT 
    fecha_trabajo,
    orden_trabajo,
    tipo_orden,
    estado,
    rgu_total,
    tipo_red,
    zona_trabajo,
    ciudad
FROM produccion
WHERE rut_tecnico = '2026-01-06T08:00:00.000Z' -- ⚠️ REEMPLAZAR CON RUT REAL
ORDER BY fecha_trabajo DESC
LIMIT 20;

-- ══════════════════════════════════════════════════════════════════
-- 5️⃣ ESTADÍSTICAS GENERALES DEL MES DE ENERO 2026
-- ══════════════════════════════════════════════════════════════════

SELECT 
    estado,
    COUNT(*) as cantidad,
    ROUND(SUM(rgu_total)::numeric, 2) as rgu_total
FROM produccion
WHERE fecha_trabajo LIKE '%/01/26%'
GROUP BY estado
ORDER BY cantidad DESC;

-- ══════════════════════════════════════════════════════════════════
-- 6️⃣ DISTRIBUCIÓN POR TIPO DE RED (TECNOLOGÍA)
-- ══════════════════════════════════════════════════════════════════

SELECT 
    tipo_red,
    COUNT(*) as cantidad,
    ROUND(AVG(rgu_total)::numeric, 2) as rgu_promedio
FROM produccion
WHERE fecha_trabajo LIKE '%/01/26%'
  AND estado = 'Completado'
GROUP BY tipo_red
ORDER BY cantidad DESC;

-- ══════════════════════════════════════════════════════════════════
-- 📋 INSTRUCCIONES PARA REGISTRO EN LA APP
-- ══════════════════════════════════════════════════════════════════

/*
1️⃣ Ejecuta la consulta 3️⃣ (OBTENER TÉCNICOS DISPONIBLES)
2️⃣ Copia el RUT de un técnico (columna rut_tecnico)
3️⃣ Abre la app TrazaBox en tu dispositivo
4️⃣ En la pantalla de registro, ingresa:
   - RUT: [el RUT que copiaste]
   - Teléfono: [cualquier número, ej: 912345678]
5️⃣ La app validará el RUT contra la tabla produccion
6️⃣ Si el RUT existe, el registro será exitoso ✅

NOTA: El campo 'rut_tecnico' en tu ejemplo de datos parece ser un timestamp:
"2026-01-06T08:00:00.000Z"

⚠️ IMPORTANTE: Verifica que el campo 'rut_tecnico' realmente contenga RUTs
y no timestamps u otros valores. Si es así, puede que necesitemos 
ajustar el AppScript o la estructura de la tabla.
*/

