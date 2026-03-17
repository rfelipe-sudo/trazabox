-- ============================================
-- DATOS DE PRODUCCIÓN PARA FEBRERO 2026
-- ============================================
-- Este script agrega órdenes de trabajo del mes actual
-- para poder ver la producción en "Tu Mes"

-- Agregar órdenes de febrero 2026 para Juan Pérez (12345678-9)
INSERT INTO produccion_traza (
    rut_tecnico, 
    tecnico, 
    fecha_trabajo, 
    orden_trabajo, 
    tipo_orden, 
    tecnologia, 
    puntos_rgu, 
    estado,
    cliente,
    comuna,
    region
)
VALUES
    -- DÍA 1 DE FEBRERO (Sábado)
    ('12345678-9', 'Juan Pérez González', '01/02/2026', 'OT-2026-010', '3_PLAY', 'FTTH', 3.00, 'Completado', 'Cliente 10', 'Santiago', 'RM'),
    ('12345678-9', 'Juan Pérez González', '01/02/2026', 'OT-2026-011', '2_PLAY', 'FTTH', 2.00, 'Completado', 'Cliente 11', 'Santiago', 'RM'),
    
    -- DÍA 3 DE FEBRERO (Lunes)
    ('12345678-9', 'Juan Pérez González', '03/02/2026', 'OT-2026-012', '3_PLAY', 'FTTH', 3.00, 'Completado', 'Cliente 12', 'Providencia', 'RM'),
    ('12345678-9', 'Juan Pérez González', '03/02/2026', 'OT-2026-013', 'MODIFICACION', 'FTTH', 0.75, 'Completado', 'Cliente 13', 'Las Condes', 'RM'),
    ('12345678-9', 'Juan Pérez González', '03/02/2026', 'OT-2026-014', '1_PLAY', 'FTTH', 1.00, 'Completado', 'Cliente 14', 'Ñuñoa', 'RM'),
    
    -- DÍA 4 DE FEBRERO (Martes - HOY)
    ('12345678-9', 'Juan Pérez González', '04/02/2026', 'OT-2026-015', '3_PLAY', 'FTTH', 3.00, 'Completado', 'Cliente 15', 'Maipú', 'RM'),
    ('12345678-9', 'Juan Pérez González', '04/02/2026', 'OT-2026-016', '2_PLAY', 'FTTH', 2.00, 'Completado', 'Cliente 16', 'Puente Alto', 'RM'),
    ('12345678-9', 'Juan Pérez González', '04/02/2026', 'OT-2026-017', 'EXTENSOR', 'FTTH', 0.75, 'Completado', 'Cliente 17', 'La Florida', 'RM'),
    
    -- También para María López (NTT)
    ('11111111-1', 'María López Silva', '03/02/2026', 'OT-2026-020', '1_PLAY', 'NTT', 1.00, 'Completado', 'Cliente 20', 'Valparaíso', 'Valparaíso'),
    ('11111111-1', 'María López Silva', '03/02/2026', 'OT-2026-021', '2_PLAY', 'NTT', 2.00, 'Completado', 'Cliente 21', 'Viña del Mar', 'Valparaíso'),
    ('11111111-1', 'María López Silva', '04/02/2026', 'OT-2026-022', '1_PLAY', 'NTT', 1.00, 'Completado', 'Cliente 22', 'Quilpué', 'Valparaíso')
ON CONFLICT DO NOTHING;

-- ============================================
-- VERIFICAR PRODUCCIÓN POR TÉCNICO
-- ============================================

-- Resumen de Juan Pérez (FTTH)
SELECT 
    rut_tecnico,
    tecnico,
    tecnologia,
    COUNT(*) as total_ordenes,
    ROUND(SUM(puntos_rgu)::numeric, 2) as total_rgu,
    COUNT(DISTINCT fecha_trabajo) as dias_trabajados,
    ROUND((SUM(puntos_rgu) / COUNT(DISTINCT fecha_trabajo))::numeric, 2) as promedio_rgu_dia
FROM produccion_traza
WHERE rut_tecnico = '12345678-9'
  AND fecha_trabajo LIKE '%/02/2026'
  AND estado = 'Completado'
GROUP BY rut_tecnico, tecnico, tecnologia;

-- Resumen de María López (NTT)
SELECT 
    rut_tecnico,
    tecnico,
    tecnologia,
    COUNT(*) as total_ordenes,
    ROUND(SUM(puntos_rgu)::numeric, 2) as total_rgu,
    COUNT(DISTINCT fecha_trabajo) as dias_trabajados,
    ROUND((SUM(puntos_rgu) / COUNT(DISTINCT fecha_trabajo))::numeric, 2) as promedio_rgu_dia
FROM produccion_traza
WHERE rut_tecnico = '11111111-1'
  AND fecha_trabajo LIKE '%/02/2026'
  AND estado = 'Completado'
GROUP BY rut_tecnico, tecnico, tecnologia;

-- Detalle por día de Juan Pérez
SELECT 
    fecha_trabajo,
    COUNT(*) as ordenes,
    STRING_AGG(tipo_orden, ', ') as tipos,
    ROUND(SUM(puntos_rgu)::numeric, 2) as rgu_dia
FROM produccion_traza
WHERE rut_tecnico = '12345678-9'
  AND fecha_trabajo LIKE '%/02/2026'
  AND estado = 'Completado'
GROUP BY fecha_trabajo
ORDER BY fecha_trabajo;

-- ============================================
-- RESULTADO ESPERADO PARA JUAN PÉREZ:
-- ============================================
-- Total RGU: 15.50
-- Promedio RGU/día: 5.17
-- Órdenes completadas: 8
-- Días trabajados: 3
-- ============================================

