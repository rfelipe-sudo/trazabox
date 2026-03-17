-- ═══════════════════════════════════════════════════════════════════
-- TABLA DE CALIDAD PARA TRAZA
-- Almacena el reporte de calidad desde Kepler
-- ═══════════════════════════════════════════════════════════════════

-- Eliminar tabla si existe (para pruebas, comentar en producción)
-- DROP TABLE IF EXISTS calidad_traza CASCADE;

-- Crear tabla principal de calidad
CREATE TABLE IF NOT EXISTS calidad_traza (
    id BIGSERIAL PRIMARY KEY,
    
    -- Identificadores
    access_id TEXT,
    orden_de_trabajo TEXT NOT NULL,
    numero_cliente TEXT,
    rut_o_bucket TEXT, -- RUT del técnico
    tecnico TEXT,
    
    -- Información del cliente
    cliente TEXT,
    
    -- Fechas y tiempos
    fecha TEXT, -- Formato DD/MM/YY
    fecha_completa DATE, -- Fecha parseada
    hora_de_reserva_de_actividad TEXT,
    
    -- Estado y tipo
    estado TEXT,
    tipo_de_actividad TEXT,
    area_derivacion TEXT,
    via_deteccion TEXT,
    
    -- Información de reiteración
    es_reiterado TEXT, -- 'SI' o 'NO'
    dias_diferencia INTEGER,
    reiterada_por_fecha TEXT,
    reiterada_por_hora_reserva TEXT,
    reiterada_por_ot TEXT,
    reiterada_por_rut_o_bucket TEXT,
    reiterada_por_tecnico TEXT,
    reiterada_por_tipo_actividad TEXT,
    
    -- Metadatos
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Índices para mejorar rendimiento
    CONSTRAINT unique_orden_fecha UNIQUE (orden_de_trabajo, fecha)
);

-- Crear índices para búsquedas rápidas
CREATE INDEX IF NOT EXISTS idx_calidad_rut_tecnico ON calidad_traza(rut_o_bucket);
CREATE INDEX IF NOT EXISTS idx_calidad_fecha ON calidad_traza(fecha);
CREATE INDEX IF NOT EXISTS idx_calidad_fecha_completa ON calidad_traza(fecha_completa);
CREATE INDEX IF NOT EXISTS idx_calidad_es_reiterado ON calidad_traza(es_reiterado);
CREATE INDEX IF NOT EXISTS idx_calidad_orden ON calidad_traza(orden_de_trabajo);
CREATE INDEX IF NOT EXISTS idx_calidad_estado ON calidad_traza(estado);

-- Crear trigger para actualizar updated_at
CREATE OR REPLACE FUNCTION update_calidad_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_calidad_updated_at
    BEFORE UPDATE ON calidad_traza
    FOR EACH ROW
    EXECUTE FUNCTION update_calidad_updated_at();

-- ═════════════════════════════════════════════════════════════════
-- VISTA: RESUMEN DE CALIDAD POR TÉCNICO Y MES
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW v_calidad_tecnicos AS
SELECT
    rut_o_bucket AS rut_tecnico,
    tecnico,
    EXTRACT(MONTH FROM fecha_completa) AS mes,
    EXTRACT(YEAR FROM fecha_completa) AS anio,
    
    -- Totales
    COUNT(*) AS total_ordenes,
    COUNT(*) FILTER (WHERE estado = 'Completado') AS ordenes_completadas,
    
    -- Reiteraciones
    COUNT(*) FILTER (WHERE es_reiterado = 'SI') AS ordenes_reiteradas,
    COUNT(*) FILTER (WHERE es_reiterado = 'NO') AS ordenes_no_reiteradas,
    
    -- Porcentaje de reiteración
    ROUND(
        (COUNT(*) FILTER (WHERE es_reiterado = 'SI')::NUMERIC / 
         NULLIF(COUNT(*) FILTER (WHERE estado = 'Completado'), 0) * 100),
        2
    ) AS porcentaje_reiteracion,
    
    -- Fechas
    MIN(fecha_completa) AS primera_fecha,
    MAX(fecha_completa) AS ultima_fecha
    
FROM calidad_traza
WHERE rut_o_bucket IS NOT NULL
  AND rut_o_bucket != ''
  AND rut_o_bucket != 'Sin Datos'
  AND fecha_completa IS NOT NULL
GROUP BY rut_o_bucket, tecnico, mes, anio
ORDER BY anio DESC, mes DESC, porcentaje_reiteracion ASC;

-- ═════════════════════════════════════════════════════════════════
-- VISTA: DETALLE DE REITERACIONES POR TÉCNICO
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW v_reiteraciones_detalle AS
SELECT
    id,
    rut_o_bucket AS rut_tecnico,
    tecnico,
    fecha,
    fecha_completa,
    orden_de_trabajo,
    cliente,
    tipo_de_actividad,
    es_reiterado,
    dias_diferencia,
    reiterada_por_fecha,
    reiterada_por_ot,
    reiterada_por_tecnico,
    reiterada_por_tipo_actividad
FROM calidad_traza
WHERE es_reiterado = 'SI'
ORDER BY fecha_completa DESC;

-- ═════════════════════════════════════════════════════════════════
-- FUNCIÓN: PARSEAR FECHA DD/MM/YY A DATE
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION parsear_fecha_calidad()
RETURNS TRIGGER AS $$
BEGIN
    -- Parsear fecha de formato DD/MM/YY a DATE
    IF NEW.fecha IS NOT NULL AND NEW.fecha != '' AND NEW.fecha != 'Sin Datos' THEN
        BEGIN
            -- Intentar parsear la fecha
            NEW.fecha_completa := TO_DATE(NEW.fecha, 'DD/MM/YY');
        EXCEPTION WHEN OTHERS THEN
            -- Si falla, dejar NULL
            NEW.fecha_completa := NULL;
        END;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear trigger para parsear fecha automáticamente
DROP TRIGGER IF EXISTS trigger_parsear_fecha_calidad ON calidad_traza;
CREATE TRIGGER trigger_parsear_fecha_calidad
    BEFORE INSERT OR UPDATE ON calidad_traza
    FOR EACH ROW
    EXECUTE FUNCTION parsear_fecha_calidad();

-- ═════════════════════════════════════════════════════════════════
-- PRUEBAS DE VERIFICACIÓN
-- ═════════════════════════════════════════════════════════════════

-- Verificar que la tabla se creó correctamente
SELECT 
    table_name, 
    column_name, 
    data_type 
FROM information_schema.columns 
WHERE table_name = 'calidad_traza'
ORDER BY ordinal_position;

-- Verificar que los índices se crearon
SELECT 
    indexname, 
    indexdef 
FROM pg_indexes 
WHERE tablename = 'calidad_traza';

-- Verificar que las vistas se crearon
SELECT 
    table_name 
FROM information_schema.views 
WHERE table_name IN ('v_calidad_tecnicos', 'v_reiteraciones_detalle');

RAISE NOTICE '✅ Tabla calidad_traza creada correctamente';
RAISE NOTICE '✅ Vistas v_calidad_tecnicos y v_reiteraciones_detalle creadas';
RAISE NOTICE '✅ Índices y triggers configurados';

