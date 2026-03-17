-- ═══════════════════════════════════════════════════════════════════
-- DEBUG: ¿Por qué la app no muestra producción?
-- ═══════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════
-- 1️⃣ SIMULAR LA CONSULTA EXACTA DE LA APP
-- ══════════════════════════════════════════════════════════════════

-- La app hace esta consulta (con RUT de ejemplo: 26402839-6)
SELECT *
FROM produccion
WHERE rut_tecnico = '26402839-6';

-- ══════════════════════════════════════════════════════════════════
-- 2️⃣ FILTRAR POR FEBRERO 2026 (como hace la app)
-- ══════════════════════════════════════════════════════════════════

-- Mes actual: Febrero 2026
SELECT 
    rut_tecnico,
    tecnico,
    fecha_trabajo,
    estado,
    rgu_total
FROM produccion
WHERE rut_tecnico = '26402839-6'
  AND fecha_trabajo LIKE '%/02/26%'  -- DD/MM/YY o DD/MM/YYYY
ORDER BY fecha_trabajo DESC;

-- ══════════════════════════════════════════════════════════════════
-- 3️⃣ VER TODOS LOS FORMATOS DE FECHA PARA ESTE TÉCNICO
-- ══════════════════════════════════════════════════════════════════

SELECT DISTINCT
    fecha_trabajo,
    LENGTH(fecha_trabajo) as longitud,
    COUNT(*) as cantidad
FROM produccion
WHERE rut_tecnico = '26402839-6'
GROUP BY fecha_trabajo, LENGTH(fecha_trabajo)
ORDER BY fecha_trabajo DESC;

-- ══════════════════════════════════════════════════════════════════
-- 4️⃣ VERIFICAR SI HAY DATOS PARA EL MES ACTUAL
-- ══════════════════════════════════════════════════════════════════

-- ¿Qué mes es HOY? Febrero 2026
SELECT 
    COUNT(*) as total_registros,
    COUNT(*) FILTER (WHERE fecha_trabajo LIKE '%/02/26%') as con_formato_corto,
    COUNT(*) FILTER (WHERE fecha_trabajo LIKE '%/02/2026%') as con_formato_largo,
    COUNT(*) FILTER (WHERE estado = 'Completado') as completados
FROM produccion
WHERE rut_tecnico = '26402839-6';

-- ══════════════════════════════════════════════════════════════════
-- 5️⃣ PROBAR CON ENERO 2026 (mes anterior)
-- ══════════════════════════════════════════════════════════════════

SELECT 
    fecha_trabajo,
    orden_trabajo,
    estado,
    rgu_total
FROM produccion
WHERE rut_tecnico = '26402839-6'
  AND (
    fecha_trabajo LIKE '%/01/26%' OR 
    fecha_trabajo LIKE '%/01/2026%'
  )
  AND estado = 'Completado'
ORDER BY fecha_trabajo DESC
LIMIT 10;

-- ══════════════════════════════════════════════════════════════════
-- 6️⃣ VERIFICAR ESTADO DE REGISTROS
-- ══════════════════════════════════════════════════════════════════

SELECT 
    estado,
    COUNT(*) as cantidad,
    ROUND(SUM(rgu_total), 2) as rgu_total
FROM produccion
WHERE rut_tecnico = '26402839-6'
GROUP BY estado;

-- ══════════════════════════════════════════════════════════════════
-- 📋 POSIBLES PROBLEMAS
-- ══════════════════════════════════════════════════════════════════

/*
PROBLEMA 1: Formato de fecha incorrecto
   - La app busca: "DD/MM/YY" (ej: 09/02/26)
   - Si la DB tiene: "DD/MM/YYYY" (ej: 09/02/2026)
   - Solución: Ver consulta 3️⃣

PROBLEMA 2: Mes incorrecto en la app
   - La app puede estar buscando Febrero, pero datos están en Enero
   - Solución: Ver consultas 4️⃣ y 5️⃣

PROBLEMA 3: Estado incorrecto
   - La app solo muestra órdenes "Completado"
   - Si hay muchas "Iniciado" o "Cancelado", no se muestran
   - Solución: Ver consulta 6️⃣

PROBLEMA 4: RUT no coincide
   - Aunque validaste el login, puede haber espacios o diferencias
   - Solución: Ver consulta 1️⃣

EJECUTA LAS 6 CONSULTAS Y COMPÁRTEME LOS RESULTADOS
*/

