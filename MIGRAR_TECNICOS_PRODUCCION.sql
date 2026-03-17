-- ═══════════════════════════════════════════════════════════════════
-- MIGRAR TÉCNICOS DE PRODUCCION A tecnicos_traza_zc
-- ═══════════════════════════════════════════════════════════════════

-- Este script:
-- 1. Inserta los RUTs válidos de produccion en tecnicos_traza_zc
-- 2. Limpia registros con timestamps en rut_tecnico

-- ══════════════════════════════════════════════════════════════════
-- 1️⃣ INSERTAR TÉCNICOS CON PRODUCCIÓN (solo RUTs válidos)
-- ══════════════════════════════════════════════════════════════════

INSERT INTO tecnicos_traza_zc (rut, nombre_completo, activo, created_at, updated_at)
SELECT DISTINCT
    p.rut_tecnico,
    p.tecnico,
    true,
    NOW(),
    NOW()
FROM produccion p
WHERE p.rut_tecnico IS NOT NULL 
  AND p.rut_tecnico != ''
  -- Solo RUTs válidos (formato XX-X o XXXXXXXX-X)
  AND p.rut_tecnico ~ '^[0-9]{7,8}-[0-9Kk]$'
  -- No insertar si ya existe
  AND NOT EXISTS (
    SELECT 1 FROM tecnicos_traza_zc t WHERE t.rut = p.rut_tecnico
  )
ORDER BY p.tecnico;

-- Ver cuántos se insertaron
SELECT 
    COUNT(*) as tecnicos_insertados,
    'Técnicos migrados desde produccion' as descripcion
FROM tecnicos_traza_zc
WHERE created_at >= NOW() - INTERVAL '1 minute';

-- ══════════════════════════════════════════════════════════════════
-- 2️⃣ OPCIONAL: LIMPIAR REGISTROS CON TIMESTAMPS COMO RUT
-- ══════════════════════════════════════════════════════════════════

-- ⚠️ CUIDADO: Esto ELIMINARÁ registros con timestamps en rut_tecnico
-- Descomenta solo si estás seguro:

/*
DELETE FROM produccion
WHERE rut_tecnico LIKE '%T08:00:00.000Z%';

SELECT COUNT(*) as registros_eliminados, 'Registros con timestamps eliminados' as descripcion;
*/

-- ══════════════════════════════════════════════════════════════════
-- 3️⃣ VERIFICAR MIGRACIÓN
-- ══════════════════════════════════════════════════════════════════

-- Ver técnicos insertados recientemente
SELECT 
    rut,
    nombre_completo,
    activo,
    created_at
FROM tecnicos_traza_zc
WHERE created_at >= NOW() - INTERVAL '5 minutes'
ORDER BY nombre_completo;

-- ══════════════════════════════════════════════════════════════════
-- 4️⃣ VERIFICAR COINCIDENCIA AHORA
-- ══════════════════════════════════════════════════════════════════

SELECT 
    t.rut,
    t.nombre_completo,
    COUNT(p.id) FILTER (WHERE p.estado = 'Completado') as ordenes_completadas,
    ROUND(SUM(p.rgu_total) FILTER (WHERE p.estado = 'Completado'), 2) as rgu_total
FROM tecnicos_traza_zc t
LEFT JOIN produccion p ON t.rut = p.rut_tecnico
WHERE t.activo = true
GROUP BY t.rut, t.nombre_completo
HAVING COUNT(p.id) FILTER (WHERE p.estado = 'Completado') > 0
ORDER BY rgu_total DESC
LIMIT 20;

-- ══════════════════════════════════════════════════════════════════
-- 5️⃣ TOP 10 TÉCNICOS CON MÁS PRODUCCIÓN (para testear login)
-- ══════════════════════════════════════════════════════════════════

SELECT 
    t.rut,
    t.nombre_completo,
    t.activo,
    COUNT(p.id) FILTER (WHERE p.estado = 'Completado' AND p.fecha_trabajo LIKE '%/02/26%') as ordenes_feb,
    ROUND(SUM(p.rgu_total) FILTER (WHERE p.estado = 'Completado' AND p.fecha_trabajo LIKE '%/02/26%'), 2) as rgu_feb
FROM tecnicos_traza_zc t
LEFT JOIN produccion p ON t.rut = p.rut_tecnico
WHERE t.activo = true
GROUP BY t.rut, t.nombre_completo, t.activo
HAVING COUNT(p.id) FILTER (WHERE p.estado = 'Completado' AND p.fecha_trabajo LIKE '%/02/26%') > 0
ORDER BY rgu_feb DESC
LIMIT 10;

-- ══════════════════════════════════════════════════════════════════
-- 📋 RESUMEN
-- ══════════════════════════════════════════════════════════════════

/*
✅ PASO 1: Ejecuta la consulta 1️⃣ (INSERT)
   - Insertará técnicos de produccion en tecnicos_traza_zc

✅ PASO 2: Ejecuta la consulta 5️⃣
   - Verás los RUTs disponibles con producción real

✅ PASO 3: Usa uno de esos RUTs para login en la app
   Ejemplo:
   - RUT: 26402839-6 (Alberto Escalona G - 42 órdenes)
   - Teléfono: 912345678

✅ PASO 4: La app ahora mostrará producción real en "Tu Mes"

⚠️ NOTA: Los registros con timestamps en rut_tecnico (ej: 2026-01-06T08:00:00.000Z)
   son datos corruptos del AppScript. Si quieres eliminarlos, descomenta la sección 2️⃣.
*/

