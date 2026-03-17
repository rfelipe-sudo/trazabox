-- ═══════════════════════════════════════════════════════════════════
-- 👥 SISTEMA DE USUARIOS TRAZA
-- ═══════════════════════════════════════════════════════════════════
-- Tabla de usuarios/técnicos para login en TrazaBox
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- PASO 1: Crear tabla de roles
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS roles (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(50) UNIQUE NOT NULL,
    descripcion TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO roles (nombre, descripcion) VALUES
('tecnico', 'Técnico en terreno'),
('supervisor', 'Supervisor de equipo'),
('ito', 'ITO (Ingeniero)'),
('bodeguero', 'Encargado de bodega'),
('admin', 'Administrador del sistema')
ON CONFLICT (nombre) DO NOTHING;

SELECT '✅ Tabla de roles creada' AS estado;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 2: Crear tabla de usuarios
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS usuarios (
    id SERIAL PRIMARY KEY,
    rut VARCHAR(12) UNIQUE NOT NULL,
    nombre VARCHAR(255) NOT NULL,
    telefono VARCHAR(20),
    email VARCHAR(255),
    rol_id INTEGER REFERENCES roles(id),
    supervisor_id INTEGER REFERENCES usuarios(id), -- Para técnicos
    tecnologia VARCHAR(20), -- 'FTTH', 'NTT', 'HFC'
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_usuarios_rut ON usuarios(rut);
CREATE INDEX IF NOT EXISTS idx_usuarios_rol ON usuarios(rol_id);
CREATE INDEX IF NOT EXISTS idx_usuarios_supervisor ON usuarios(supervisor_id);

COMMENT ON TABLE usuarios IS 
'Usuarios del sistema TrazaBox (técnicos, supervisores, etc.)';

SELECT '✅ Tabla de usuarios creada' AS estado;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 3: Crear función RPC para login
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION get_usuario_por_rut(p_rut VARCHAR)
RETURNS TABLE (
    id INTEGER,
    rut VARCHAR,
    nombre VARCHAR,
    telefono VARCHAR,
    email VARCHAR,
    rol_id INTEGER,
    rol_nombre VARCHAR,
    supervisor_id INTEGER,
    tecnologia VARCHAR,
    activo BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.id,
        u.rut,
        u.nombre,
        u.telefono,
        u.email,
        u.rol_id,
        r.nombre AS rol_nombre,
        u.supervisor_id,
        u.tecnologia,
        u.activo
    FROM usuarios u
    INNER JOIN roles r ON u.rol_id = r.id
    WHERE u.rut = p_rut
      AND u.activo = TRUE
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_usuario_por_rut IS 
'Función para login: busca usuario por RUT y retorna sus datos con rol';

SELECT '✅ Función get_usuario_por_rut creada' AS estado;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 4: Insertar usuarios de prueba
-- ═══════════════════════════════════════════════════════════════════

-- Obtener IDs de roles
DO $$
DECLARE
    v_rol_tecnico INTEGER;
    v_rol_supervisor INTEGER;
    v_rol_admin INTEGER;
BEGIN
    SELECT id INTO v_rol_tecnico FROM roles WHERE nombre = 'tecnico';
    SELECT id INTO v_rol_supervisor FROM roles WHERE nombre = 'supervisor';
    SELECT id INTO v_rol_admin FROM roles WHERE nombre = 'admin';
    
    -- Insertar usuarios de prueba
    INSERT INTO usuarios (rut, nombre, telefono, rol_id, tecnologia, activo) VALUES
    -- Administrador
    ('11111111-1', 'Admin TRAZA', '+56900000000', v_rol_admin, NULL, TRUE),
    
    -- Supervisores
    ('12345678-9', 'Supervisor 1 TRAZA', '+56911111111', v_rol_supervisor, NULL, TRUE),
    ('98765432-1', 'Supervisor 2 TRAZA', '+56922222222', v_rol_supervisor, NULL, TRUE),
    
    -- Técnicos FTTH (supervisor_id = 2, que es el Supervisor 1)
    ('15000000-1', 'Juan Pérez (FTTH)', '+56933333333', v_rol_tecnico, 'FTTH', TRUE),
    ('15000000-2', 'María González (FTTH)', '+56944444444', v_rol_tecnico, 'FTTH', TRUE),
    ('15000000-3', 'Pedro Rojas (FTTH)', '+56955555555', v_rol_tecnico, 'FTTH', TRUE),
    ('15000000-4', 'Ana Silva (FTTH)', '+56966666666', v_rol_tecnico, 'FTTH', TRUE),
    ('15000000-5', 'Carlos Muñoz (FTTH)', '+56977777777', v_rol_tecnico, 'FTTH', TRUE),
    
    -- Técnicos NTT (supervisor_id = 3, que es el Supervisor 2)
    ('16000000-1', 'Luis Torres (NTT)', '+56988888888', v_rol_tecnico, 'NTT', TRUE),
    ('16000000-2', 'Sandra Díaz (NTT)', '+56999999999', v_rol_tecnico, 'NTT', TRUE),
    ('16000000-3', 'Jorge Vega (NTT)', '+56900000001', v_rol_tecnico, 'NTT', TRUE),
    ('16000000-4', 'Patricia Morales (NTT)', '+56900000002', v_rol_tecnico, 'NTT', TRUE),
    ('16000000-5', 'Roberto Castro (NTT)', '+56900000003', v_rol_tecnico, 'NTT', TRUE)
    
    ON CONFLICT (rut) DO NOTHING;
    
    -- Actualizar supervisor_id de los técnicos
    UPDATE usuarios 
    SET supervisor_id = 2 -- ID del Supervisor 1
    WHERE rol_id = v_rol_tecnico 
      AND tecnologia = 'FTTH';
    
    UPDATE usuarios 
    SET supervisor_id = 3 -- ID del Supervisor 2
    WHERE rol_id = v_rol_tecnico 
      AND tecnologia = 'NTT';
END $$;

SELECT '✅ Usuarios de prueba insertados' AS estado;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 5: Verificar instalación
-- ═══════════════════════════════════════════════════════════════════

SELECT '📊 RESUMEN DE USUARIOS:' AS titulo;
SELECT '' AS separador;

-- Por rol
SELECT 
    r.nombre AS rol,
    COUNT(u.id) AS cantidad_usuarios
FROM roles r
LEFT JOIN usuarios u ON r.id = u.rol_id AND u.activo = TRUE
GROUP BY r.nombre
ORDER BY r.nombre;

SELECT '' AS separador;

-- Por tecnología (solo técnicos)
SELECT 
    COALESCE(tecnologia, 'Sin tecnología') AS tecnologia,
    COUNT(*) AS cantidad_tecnicos
FROM usuarios
WHERE rol_id = (SELECT id FROM roles WHERE nombre = 'tecnico')
  AND activo = TRUE
GROUP BY tecnologia
ORDER BY tecnologia;

SELECT '' AS separador;

-- Lista de usuarios activos
SELECT 
    '👥 USUARIOS ACTIVOS:' AS titulo;
    
SELECT 
    u.rut,
    u.nombre,
    r.nombre AS rol,
    u.tecnologia,
    CASE 
        WHEN u.supervisor_id IS NOT NULL THEN 
            (SELECT nombre FROM usuarios WHERE id = u.supervisor_id)
        ELSE NULL
    END AS supervisor
FROM usuarios u
INNER JOIN roles r ON u.rol_id = r.id
WHERE u.activo = TRUE
ORDER BY r.nombre, u.tecnologia, u.nombre;

SELECT '' AS separador;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 6: Probar función de login
-- ═══════════════════════════════════════════════════════════════════

SELECT '🧪 PRUEBA DE LOGIN:' AS titulo;
SELECT '' AS separador;

-- Probar login con técnico FTTH
SELECT 
    '✅ Login técnico FTTH (15000000-1):' AS test,
    * 
FROM get_usuario_por_rut('15000000-1');

SELECT '' AS separador;

-- Probar login con técnico NTT
SELECT 
    '✅ Login técnico NTT (16000000-1):' AS test,
    * 
FROM get_usuario_por_rut('16000000-1');

SELECT '' AS separador;

-- Probar login con supervisor
SELECT 
    '✅ Login supervisor (12345678-9):' AS test,
    * 
FROM get_usuario_por_rut('12345678-9');

SELECT '' AS separador;

-- Probar login con RUT inexistente
SELECT 
    '⚠️ Login RUT inexistente (99999999-9):' AS test,
    * 
FROM get_usuario_por_rut('99999999-9');

SELECT '' AS separador;
SELECT '✅ SISTEMA DE USUARIOS LISTO' AS estado_final;

-- ═══════════════════════════════════════════════════════════════════
-- 📝 NOTAS DE USO
-- ═══════════════════════════════════════════════════════════════════
/*
USUARIOS DE PRUEBA CREADOS:

ADMIN:
- RUT: 11111111-1
- Nombre: Admin TRAZA

SUPERVISORES:
- RUT: 12345678-9 | Supervisor 1 TRAZA
- RUT: 98765432-1 | Supervisor 2 TRAZA

TÉCNICOS FTTH (bajo Supervisor 1):
- 15000000-1 | Juan Pérez (FTTH)
- 15000000-2 | María González (FTTH)
- 15000000-3 | Pedro Rojas (FTTH)
- 15000000-4 | Ana Silva (FTTH)
- 15000000-5 | Carlos Muñoz (FTTH)

TÉCNICOS NTT (bajo Supervisor 2):
- 16000000-1 | Luis Torres (NTT)
- 16000000-2 | Sandra Díaz (NTT)
- 16000000-3 | Jorge Vega (NTT)
- 16000000-4 | Patricia Morales (NTT)
- 16000000-5 | Roberto Castro (NTT)

PARA AGREGAR MÁS USUARIOS:
INSERT INTO usuarios (rut, nombre, telefono, rol_id, tecnologia, supervisor_id, activo) 
VALUES (
    '17000000-1',
    'Nuevo Técnico',
    '+56900000010',
    (SELECT id FROM roles WHERE nombre = 'tecnico'),
    'FTTH',
    2, -- ID del supervisor
    TRUE
);

PARA PROBAR LOGIN EN LA APP:
Ingresa solo el RUT sin puntos ni guión: 150000001
*/

