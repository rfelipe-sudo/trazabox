-- ============================================
-- VERIFICAR Y AJUSTAR DATOS REALES DE TRAZA
-- ============================================

-- PASO 1: Ver si ya hay datos en la tabla
SELECT 
    COUNT(*) as total_registros,
    COUNT(DISTINCT rut_tecnico) as total_tecnicos,
    MIN(fecha_trabajo) as fecha_mas_antigua,
    MAX(fecha_trabajo) as fecha_mas_reciente
FROM produccion_traza;

-- PASO 2: Ver técnicos únicos con producción
SELECT 
    rut_tecnico,
    tecnico,
    COUNT(*) as total_ordenes,
    COUNT(CASE WHEN estado = 'Completado' THEN 1 END) as completadas,
    ROUND(SUM(CASE WHEN estado = 'Completado' THEN COALESCE(rgu_total, puntos_rgu, 0) ELSE 0 END)::numeric, 2) as rgu_total
FROM produccion_traza
GROUP BY rut_tecnico, tecnico
ORDER BY rgu_total DESC
LIMIT 20;

-- PASO 3: Ver producción de febrero 2026
SELECT 
    rut_tecnico,
    tecnico,
    COUNT(*) as ordenes_feb,
    ROUND(SUM(COALESCE(rgu_total, puntos_rgu, 0))::numeric, 2) as rgu_feb
FROM produccion_traza
WHERE fecha_trabajo LIKE '%/02/26'
  AND estado = 'Completado'
GROUP BY rut_tecnico, tecnico
ORDER BY rgu_feb DESC
LIMIT 10;

-- ============================================
-- AJUSTES SI ES NECESARIO
-- ============================================

-- AJUSTE 1: Si la columna se llama puntos_rgu pero el AppScript guarda en rgu_total
-- Verificar qué columnas existen:
SELECT column_name 
FROM information_schema.columns 
WHERE table_name = 'produccion_traza' 
  AND column_name IN ('rgu_total', 'puntos_rgu');

-- Si existe rgu_total pero no puntos_rgu, agregar alias:
ALTER TABLE produccion_traza 
ADD COLUMN IF NOT EXISTS puntos_rgu NUMERIC(3,2) 
GENERATED ALWAYS AS (rgu_total) STORED;

-- O viceversa: si existe puntos_rgu pero el AppScript guarda en rgu_total:
-- No es necesario, el AppScript ya guarda en rgu_total

-- AJUSTE 2: Agregar columna tecnologia si no existe
ALTER TABLE produccion_traza 
ADD COLUMN IF NOT EXISTS tecnologia VARCHAR(20);

-- Actualizar tecnología para registros existentes (si tipo_red existe)
UPDATE produccion_traza 
SET tecnologia = CASE 
    WHEN UPPER(tipo_red) LIKE '%FTTH%' OR UPPER(tipo_red) LIKE '%GPON%' THEN 'FTTH'
    WHEN UPPER(tipo_red) LIKE '%NTT%' OR UPPER(tipo_red) LIKE '%NEUTR%' THEN 'NTT'
    WHEN UPPER(tipo_red) LIKE '%HFC%' OR UPPER(tipo_red) LIKE '%COAX%' THEN 'HFC'
    ELSE 'FTTH'
END
WHERE tecnologia IS NULL;

-- Verificar actualización
SELECT tecnologia, COUNT(*) 
FROM produccion_traza 
GROUP BY tecnologia;

-- ============================================
-- VERIFICACIÓN FINAL: ¿Listo para la app?
-- ============================================

-- Verificar que todos los campos necesarios existen
SELECT 
    EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name = 'produccion_traza' AND column_name = 'rut_tecnico') as tiene_rut,
    EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name = 'produccion_traza' AND column_name = 'tecnico') as tiene_tecnico,
    EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name = 'produccion_traza' AND column_name = 'fecha_trabajo') as tiene_fecha,
    EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name = 'produccion_traza' AND column_name = 'orden_trabajo') as tiene_orden,
    EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name = 'produccion_traza' AND column_name = 'tipo_orden') as tiene_tipo,
    EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name = 'produccion_traza' AND column_name = 'tecnologia') as tiene_tecnologia,
    EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name = 'produccion_traza' AND column_name = 'estado') as tiene_estado,
    EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name = 'produccion_traza' AND (column_name = 'rgu_total' OR column_name = 'puntos_rgu')) as tiene_rgu;

-- ============================================
-- OBTENER UN TÉCNICO REAL PARA PROBAR
-- ============================================

-- Técnico con más producción en febrero
SELECT 
    rut_tecnico,
    tecnico,
    tecnologia,
    COUNT(*) as ordenes,
    ROUND(SUM(COALESCE(rgu_total, puntos_rgu, 0))::numeric, 2) as rgu_total
FROM produccion_traza
WHERE fecha_trabajo LIKE '%/02/26'
  AND estado = 'Completado'
  AND rut_tecnico IS NOT NULL
  AND rut_tecnico != ''
GROUP BY rut_tecnico, tecnico, tecnologia
ORDER BY rgu_total DESC
LIMIT 1;

-- ============================================
-- RESULTADO ESPERADO:
-- ============================================
-- Copia el RUT y nombre del técnico de la consulta anterior
-- Ejemplo:
-- rut_tecnico: 12345678-9
-- tecnico: Juan Pérez
-- tecnologia: FTTH
-- ordenes: 15
-- rgu_total: 25.50
--
-- Usa ese RUT para registrarte en la app
-- ============================================

