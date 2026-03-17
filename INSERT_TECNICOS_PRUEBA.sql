-- ============================================
-- INSERTAR TÉCNICOS DE PRUEBA EN TRAZA
-- ============================================
-- Este script inserta técnicos en produccion_traza
-- con la estructura correcta para el registro en la app

-- Insertar órdenes de trabajo para técnicos de prueba
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
    -- Técnico FTTH #1
    ('12345678-9', 'Juan Pérez González', '04/02/2026', 'OT-2026-001', '3_PLAY', 'FTTH', 3.00, 'Completado', 'Cliente Demo 1', 'Santiago', 'Región Metropolitana'),
    
    -- Técnico NTT #1
    ('11111111-1', 'María López Silva', '04/02/2026', 'OT-2026-002', '1_PLAY', 'NTT', 1.00, 'Completado', 'Cliente Demo 2', 'Valparaíso', 'Valparaíso'),
    
    -- Supervisor FTTH
    ('22222222-2', 'Carlos Ramírez Torres', '04/02/2026', 'OT-2026-003', '3_PLAY', 'FTTH', 3.00, 'Completado', 'Cliente Demo 3', 'Concepción', 'Biobío'),
    
    -- Técnico FTTH #2
    ('33333333-3', 'Andrea Muñoz Díaz', '04/02/2026', 'OT-2026-004', '2_PLAY', 'FTTH', 2.00, 'Completado', 'Cliente Demo 4', 'La Serena', 'Coquimbo'),
    
    -- Técnico FTTH #3
    ('44444444-4', 'Roberto Castro Vega', '04/02/2026', 'OT-2026-005', 'MODIFICACION', 'FTTH', 0.75, 'Completado', 'Cliente Demo 5', 'Antofagasta', 'Antofagasta'),
    
    -- Técnico NTT #2
    ('55555555-5', 'Claudia Soto Rojas', '04/02/2026', 'OT-2026-006', '1_PLAY', 'NTT', 1.00, 'Completado', 'Cliente Demo 6', 'Temuco', 'Araucanía'),
    
    -- Técnico NTT #3
    ('66666666-6', 'Diego Herrera Ponce', '04/02/2026', 'OT-2026-007', '2_PLAY', 'NTT', 2.00, 'Completado', 'Cliente Demo 7', 'Puerto Montt', 'Los Lagos')
ON CONFLICT DO NOTHING;

-- Verificar datos insertados
SELECT 
    rut_tecnico, 
    tecnico, 
    tecnologia, 
    COUNT(*) as ordenes_count,
    SUM(puntos_rgu) as total_rgu
FROM produccion_traza 
GROUP BY rut_tecnico, tecnico, tecnologia
ORDER BY rut_tecnico;

-- ============================================
-- CREDENCIALES PARA REGISTRO EN LA APP:
-- ============================================
-- 
-- 1. RUT: 12345678-9
--    Nombre: Juan Pérez González
--    Tecnología: FTTH
--    Teléfono: (cualquier número, ej: +56912345678)
--
-- 2. RUT: 11111111-1
--    Nombre: María López Silva
--    Tecnología: NTT
--    Teléfono: (cualquier número, ej: +56987654321)
--
-- 3. RUT: 22222222-2
--    Nombre: Carlos Ramírez Torres
--    Tecnología: FTTH
--    Teléfono: (cualquier número, ej: +56911111111)
--
-- 4. RUT: 33333333-3
--    Nombre: Andrea Muñoz Díaz
--    Tecnología: FTTH
--    Teléfono: (cualquier número, ej: +56922222222)
--
-- 5. RUT: 44444444-4
--    Nombre: Roberto Castro Vega
--    Tecnología: FTTH
--    Teléfono: (cualquier número, ej: +56933333333)
--
-- 6. RUT: 55555555-5
--    Nombre: Claudia Soto Rojas
--    Tecnología: NTT
--    Teléfono: (cualquier número, ej: +56944444444)
--
-- 7. RUT: 66666666-6
--    Nombre: Diego Herrera Ponce
--    Tecnología: NTT
--    Teléfono: (cualquier número, ej: +56955555555)
-- ============================================

