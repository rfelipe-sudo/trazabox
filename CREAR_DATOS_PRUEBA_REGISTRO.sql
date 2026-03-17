-- ============================================
-- DATOS DE PRUEBA PARA REGISTRO EN TRAZABOX
-- ============================================
-- Este script crea datos mínimos necesarios para 
-- que los técnicos puedan registrarse en la app

-- Crear tabla produccion_traza si no existe (adaptada de produccion_crea)
CREATE TABLE IF NOT EXISTS produccion_traza (
    id SERIAL PRIMARY KEY,
    rut_tecnico VARCHAR(12) NOT NULL,
    tecnico VARCHAR(255) NOT NULL,
    fecha_trabajo VARCHAR(20),
    numero_ot VARCHAR(50),
    tipo_orden VARCHAR(100),
    tecnologia VARCHAR(10) DEFAULT 'FTTH',
    estado VARCHAR(50) DEFAULT 'Completado',
    rgu_total NUMERIC(10,2) DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Insertar técnicos de prueba para que puedan registrarse
-- Estos RUTs se pueden usar en la pantalla de registro
INSERT INTO produccion_traza (rut_tecnico, tecnico, tecnologia, estado, rgu_total, fecha_trabajo, numero_ot, tipo_orden)
VALUES
    -- Técnico FTTH
    ('12345678-9', 'Juan Pérez González', 'FTTH', 'Completado', 2.5, '04/02/2026', 'OT-2026-001', 'Instalación 3 Play'),
    
    -- Técnico NTT
    ('11111111-1', 'María López Silva', 'NTT', 'Completado', 1.0, '04/02/2026', 'OT-2026-002', 'Instalación 1 Play'),
    
    -- Supervisor
    ('22222222-2', 'Carlos Ramírez Torres', 'FTTH', 'Completado', 3.0, '04/02/2026', 'OT-2026-003', 'Instalación 3 Play'),
    
    -- Más técnicos FTTH
    ('33333333-3', 'Andrea Muñoz Díaz', 'FTTH', 'Completado', 2.0, '04/02/2026', 'OT-2026-004', 'Instalación 2 Play'),
    ('44444444-4', 'Roberto Castro Vega', 'FTTH', 'Completado', 1.5, '04/02/2026', 'OT-2026-005', 'Modificación'),
    
    -- Más técnicos NTT
    ('55555555-5', 'Claudia Soto Rojas', 'NTT', 'Completado', 1.0, '04/02/2026', 'OT-2026-006', 'Instalación 1 Play'),
    ('66666666-6', 'Diego Herrera Ponce', 'NTT', 'Completado', 2.0, '04/02/2026', 'OT-2026-007', 'Instalación 2 Play')
ON CONFLICT DO NOTHING;

-- Crear índice para búsquedas rápidas por RUT
CREATE INDEX IF NOT EXISTS idx_produccion_traza_rut ON produccion_traza(rut_tecnico);

-- Verificar datos insertados
SELECT rut_tecnico, tecnico, tecnologia 
FROM produccion_traza 
ORDER BY rut_tecnico;

-- ============================================
-- CREDENCIALES PARA REGISTRO:
-- ============================================
-- RUT: 12345678-9 | Nombre: Juan Pérez González | Tech: FTTH
-- RUT: 11111111-1 | Nombre: María López Silva | Tech: NTT
-- RUT: 22222222-2 | Nombre: Carlos Ramírez Torres | Tech: FTTH (Supervisor)
-- RUT: 33333333-3 | Nombre: Andrea Muñoz Díaz | Tech: FTTH
-- RUT: 44444444-4 | Nombre: Roberto Castro Vega | Tech: FTTH
-- RUT: 55555555-5 | Nombre: Claudia Soto Rojas | Tech: NTT
-- RUT: 66666666-6 | Nombre: Diego Herrera Ponce | Tech: NTT
-- ============================================
-- Teléfono: Cualquier número (ej: +56912345678)
-- ============================================

