-- ═══════════════════════════════════════════════════════════════════
-- MIGRAR TÉCNICOS DE PRODUCCION A tecnicos_traza_zc (SIN DUPLICADOS)
-- ═══════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════
-- 1️⃣ INSERTAR SOLO TÉCNICOS NUEVOS (ignorar duplicados)
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
ORDER BY p.tecnico
ON CONFLICT (rut) DO NOTHING;  -- Ignorar duplicados

-- Ver cuántos se insertaron
SELECT 
    (SELECT COUNT(*) FROM tecnicos_traza_zc) as total_tecnicos,
    (SELECT COUNT(*) FROM tecnicos_traza_zc WHERE created_at >= NOW() - INTERVAL '1 minute') as recien_insertados;

-- ══════════════════════════════════════════════════════════════════
-- 2️⃣ VERIFICAR TÉCNICOS CON PRODUCCIÓN EN FEBRERO 2026
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
LIMIT 20;

-- ══════════════════════════════════════════════════════════════════
-- 3️⃣ VERIFICAR TÉCNICOS CON PRODUCCIÓN EN ENERO 2026
-- ══════════════════════════════════════════════════════════════════

SELECT 
    t.rut,
    t.nombre_completo,
    t.activo,
    COUNT(p.id) FILTER (WHERE p.estado = 'Completado' AND p.fecha_trabajo LIKE '%/01/26%') as ordenes_ene,
    ROUND(SUM(p.rgu_total) FILTER (WHERE p.estado = 'Completado' AND p.fecha_trabajo LIKE '%/01/26%'), 2) as rgu_ene
FROM tecnicos_traza_zc t
LEFT JOIN produccion p ON t.rut = p.rut_tecnico
WHERE t.activo = true
GROUP BY t.rut, t.nombre_completo, t.activo
HAVING COUNT(p.id) FILTER (WHERE p.estado = 'Completado' AND p.fecha_trabajo LIKE '%/01/26%') > 0
ORDER BY rgu_ene DESC
LIMIT 20;

-- ══════════════════════════════════════════════════════════════════
-- 📋 INSTRUCCIONES
-- ══════════════════════════════════════════════════════════════════

/*
✅ Ejecuta la consulta 1️⃣ 
   - Se insertarán solo los técnicos nuevos
   - Los duplicados se ignorarán automáticamente

✅ Ejecuta la consulta 2️⃣ (Febrero) o 3️⃣ (Enero)
   - Verás los RUTs disponibles con producción

✅ Usa uno de esos RUTs para login:
   - RUT: [copia de la consulta]
   - Teléfono: 912345678

✅ La app mostrará producción real en "Tu Mes"
*/

