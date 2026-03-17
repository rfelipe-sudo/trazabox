-- ═══════════════════════════════════════════════════════════════════
-- DIAGNÓSTICO: ¿Por qué no se muestran datos de producción?
-- ═══════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════
-- 1️⃣ VERIFICAR COINCIDENCIA DE RUTS
-- ══════════════════════════════════════════════════════════════════

-- Ver si los RUTs de tecnicos_traza_zc existen en produccion
SELECT 
    t.rut as rut_en_tecnicos,
    t.nombre_completo,
    p.rut_tecnico as rut_en_produccion,
    COUNT(p.id) as ordenes_encontradas
FROM tecnicos_traza_zc t
LEFT JOIN produccion p ON t.rut = p.rut_tecnico
WHERE t.activo = true
GROUP BY t.rut, t.nombre_completo, p.rut_tecnico
ORDER BY ordenes_encontradas DESC
LIMIT 20;

-- ══════════════════════════════════════════════════════════════════
-- 2️⃣ EJEMPLO: ABRAHAM ANDRES MARTINEZ LOBOS (21541724-7)
-- ══════════════════════════════════════════════════════════════════

-- ¿Existe producción para este RUT?
SELECT 
    rut_tecnico,
    tecnico,
    fecha_trabajo,
    orden_trabajo,
    estado,
    rgu_total
FROM produccion
WHERE rut_tecnico = '21541724-7'
ORDER BY fecha_trabajo DESC
LIMIT 10;

-- ══════════════════════════════════════════════════════════════════
-- 3️⃣ FORMATO DE FECHA EN PRODUCCION
-- ══════════════════════════════════════════════════════════════════

-- Ver ejemplos de fechas en produccion
SELECT DISTINCT
    fecha_trabajo,
    COUNT(*) as cantidad
FROM produccion
GROUP BY fecha_trabajo
ORDER BY cantidad DESC
LIMIT 20;

-- ══════════════════════════════════════════════════════════════════
-- 4️⃣ TÉCNICOS CON PRODUCCIÓN (cualquier RUT)
-- ══════════════════════════════════════════════════════════════════

SELECT 
    rut_tecnico,
    tecnico,
    COUNT(*) as ordenes_completadas,
    ROUND(SUM(rgu_total)::numeric, 2) as rgu_total,
    MAX(fecha_trabajo) as ultima_fecha
FROM produccion
WHERE estado = 'Completado'
  AND rut_tecnico IS NOT NULL
  AND rut_tecnico != ''
GROUP BY rut_tecnico, tecnico
ORDER BY rgu_total DESC
LIMIT 20;

-- ══════════════════════════════════════════════════════════════════
-- 5️⃣ CRUCE COMPLETO: Técnicos Activos + Producción de Febrero 2026
-- ══════════════════════════════════════════════════════════════════

SELECT 
    t.rut,
    t.nombre_completo,
    COUNT(p.id) FILTER (WHERE p.estado = 'Completado' AND p.fecha_trabajo LIKE '%/02/26%') as ordenes_feb,
    ROUND(SUM(p.rgu_total) FILTER (WHERE p.estado = 'Completado' AND p.fecha_trabajo LIKE '%/02/26%'), 2) as rgu_feb
FROM tecnicos_traza_zc t
LEFT JOIN produccion p ON t.rut = p.rut_tecnico
WHERE t.activo = true
GROUP BY t.rut, t.nombre_completo
HAVING COUNT(p.id) FILTER (WHERE p.estado = 'Completado' AND p.fecha_trabajo LIKE '%/02/26%') > 0
ORDER BY rgu_feb DESC;

-- ══════════════════════════════════════════════════════════════════
-- 📋 INSTRUCCIONES DE DIAGNÓSTICO
-- ══════════════════════════════════════════════════════════════════

/*
PASO 1: Ejecuta la consulta 1️⃣
   - Si ves ordenes_encontradas > 0 → HAY coincidencia de RUTs ✅
   - Si ves ordenes_encontradas = 0 para TODOS → NO hay coincidencia ❌

PASO 2: Ejecuta la consulta 4️⃣
   - Compara los rut_tecnico de produccion con los rut de tecnicos_traza_zc
   - ¿Son iguales o diferentes?

POSIBLES PROBLEMAS:

❌ Problema A: RUTs no coinciden
   - En tecnicos_traza_zc: 21541724-7
   - En produccion: puede estar en otro formato o campo

❌ Problema B: Fechas incorrectas
   - La app busca fechas como: "DD/MM/YY" o "DD/MM/YYYY"
   - Si el formato es distinto, no encontrará datos

❌ Problema C: Campo rut_tecnico vacío en produccion
   - Los datos están en codigo_tecnico u otro campo

COMPARTE LOS RESULTADOS de las consultas 1️⃣ y 4️⃣
*/

