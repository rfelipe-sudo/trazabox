-- ============================================
-- FIX: DATOS DE PRUEBA PARA REGISTRO EN TRAZABOX
-- ============================================
-- Este script se adapta a la estructura existente de produccion_traza

-- Primero, verificar qué columnas tiene la tabla
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'produccion_traza'
ORDER BY ordinal_position;

-- Eliminar datos existentes si los hay (opcional, comentar si quieres mantenerlos)
-- TRUNCATE TABLE produccion_traza;

-- Insertar técnicos de prueba SOLO con las columnas que existen
-- Ajusta este INSERT según las columnas que te mostró la consulta anterior
INSERT INTO produccion_traza (rut_tecnico, tecnico, tecnologia)
VALUES
    ('12345678-9', 'Juan Pérez González', 'FTTH'),
    ('11111111-1', 'María López Silva', 'NTT'),
    ('22222222-2', 'Carlos Ramírez Torres', 'FTTH'),
    ('33333333-3', 'Andrea Muñoz Díaz', 'FTTH'),
    ('44444444-4', 'Roberto Castro Vega', 'FTTH'),
    ('55555555-5', 'Claudia Soto Rojas', 'NTT'),
    ('66666666-6', 'Diego Herrera Ponce', 'NTT')
ON CONFLICT DO NOTHING;

-- Verificar datos insertados
SELECT rut_tecnico, tecnico, tecnologia 
FROM produccion_traza 
ORDER BY rut_tecnico;

-- ============================================
-- CREDENCIALES PARA REGISTRO:
-- ============================================
-- RUT: 12345678-9 | Nombre: Juan Pérez González | Tech: FTTH
-- RUT: 11111111-1 | Nombre: María López Silva | Tech: NTT
-- RUT: 22222222-2 | Nombre: Carlos Ramírez Torres | Tech: FTTH
-- RUT: 33333333-3 | Nombre: Andrea Muñoz Díaz | Tech: FTTH
-- RUT: 44444444-4 | Nombre: Roberto Castro Vega | Tech: FTTH
-- RUT: 55555555-5 | Nombre: Claudia Soto Rojas | Tech: NTT
-- RUT: 66666666-6 | Nombre: Diego Herrera Ponce | Tech: NTT
-- ============================================
-- Teléfono: Cualquier número (ej: +56912345678)
-- ============================================

