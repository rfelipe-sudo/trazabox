-- ═══════════════════════════════════════════════════════════════════
-- VERIFICAR TÉCNICOS ACTIVOS EN tecnicos_traza_zc
-- ═══════════════════════════════════════════════════════════════════

-- Proyecto Supabase: szoywhtkilgvfrczuyqn

-- ══════════════════════════════════════════════════════════════════
-- 1️⃣ TÉCNICOS ACTIVOS DISPONIBLES PARA REGISTRO
-- ══════════════════════════════════════════════════════════════════

SELECT 
    rut,
    nombre_completo,
    activo,
    created_at
FROM tecnicos_traza_zc
WHERE activo = true
ORDER BY nombre_completo;

-- ══════════════════════════════════════════════════════════════════
-- 2️⃣ TÉCNICOS CON PRODUCCIÓN (cruce con tabla produccion)
-- ══════════════════════════════════════════════════════════════════

SELECT 
    t.rut,
    t.nombre_completo,
    t.activo,
    COUNT(p.id) as ordenes_completadas,
    ROUND(SUM(p.rgu_total)::numeric, 2) as rgu_total,
    MAX(p.fecha_trabajo) as ultima_actividad
FROM tecnicos_traza_zc t
LEFT JOIN produccion p ON t.rut = p.rut_tecnico
WHERE t.activo = true
  AND (p.estado = 'Completado' OR p.estado IS NULL)
  AND (p.fecha_trabajo LIKE '%/01/26%' OR p.fecha_trabajo LIKE '%/02/26%' OR p.fecha_trabajo IS NULL)
GROUP BY t.rut, t.nombre_completo, t.activo
ORDER BY rgu_total DESC NULLS LAST;

-- ══════════════════════════════════════════════════════════════════
-- 3️⃣ VERIFICAR UN RUT ESPECÍFICO
-- ══════════════════════════════════════════════════════════════════

-- Reemplaza '25124619-K' con el RUT que quieras verificar
SELECT 
    rut,
    nombre_completo,
    activo,
    created_at,
    updated_at
FROM tecnicos_traza_zc
WHERE rut = '25124619-K';

-- ══════════════════════════════════════════════════════════════════
-- 4️⃣ TOTAL DE TÉCNICOS ACTIVOS VS INACTIVOS
-- ══════════════════════════════════════════════════════════════════

SELECT 
    activo,
    COUNT(*) as cantidad
FROM tecnicos_traza_zc
GROUP BY activo;

-- ══════════════════════════════════════════════════════════════════
-- 5️⃣ TÉCNICOS SIN PRODUCCIÓN REGISTRADA
-- ══════════════════════════════════════════════════════════════════

SELECT 
    t.rut,
    t.nombre_completo,
    t.activo
FROM tecnicos_traza_zc t
LEFT JOIN produccion p ON t.rut = p.rut_tecnico
WHERE t.activo = true
  AND p.id IS NULL
ORDER BY t.nombre_completo;

-- ══════════════════════════════════════════════════════════════════
-- 📋 INSTRUCCIONES PARA REGISTRO EN LA APP
-- ══════════════════════════════════════════════════════════════════

/*
1️⃣ Ejecuta la consulta 1️⃣ o 2️⃣ para ver los técnicos disponibles

2️⃣ Copia un RUT de la lista (ejemplo: 25124619-K)

3️⃣ Compila la app si aún no lo has hecho:
   cd C:\Users\Usuario\trazabox
   flutter clean
   flutter pub get
   flutter build apk --release

4️⃣ Instala el APK en tu dispositivo

5️⃣ Abre TrazaBox y regístrate con:
   - RUT: [el RUT que copiaste]
   - Teléfono: [cualquier número, ej: 912345678]

6️⃣ La app validará contra tecnicos_traza_zc:
   ✅ RUT existe + activo = true → Registro exitoso
   ❌ RUT no existe o activo = false → Error

NOTA: La app ahora valida contra tecnicos_traza_zc (técnicos autorizados)
      en lugar de la tabla produccion.
*/

