-- ═══════════════════════════════════════════════════════════════════
-- VISTA calidad_api_script
-- La app consulta calidad_api_script con columna periodo (MM-YYYY).
-- calidad_traza no tiene periodo; se deriva de fecha_completa.
-- Esta vista expone calidad_traza con el formato esperado.
-- ═══════════════════════════════════════════════════════════════════

DROP VIEW IF EXISTS calidad_api_script;

CREATE OR REPLACE VIEW calidad_api_script AS
SELECT
    id,
    access_id,
    orden_de_trabajo,
    numero_cliente,
    rut_o_bucket,
    tecnico,
    cliente,
    fecha,
    hora_de_reserva_de_actividad,
    estado,
    tipo_de_actividad,
    area_derivacion,
    via_deteccion,
    -- es_reiterado: calidad_traza usa 'SI'/'NO'; la app espera boolean
    (COALESCE(UPPER(TRIM(es_reiterado::TEXT)), '') = 'SI') AS es_reiterado,
    dias_diferencia,
    reiterada_por_fecha,
    reiterada_por_hora_reserva,
    reiterada_por_ot,
    reiterada_por_rut_o_bucket,
    reiterada_por_tecnico,
    reiterada_por_tipo_actividad,
    -- periodo en formato MM-YYYY (mes de trabajo)
    TO_CHAR(fecha_completa, 'MM-YYYY') AS periodo,
    created_at,
    updated_at
FROM calidad_traza
WHERE fecha_completa IS NOT NULL
  AND rut_o_bucket IS NOT NULL
  AND rut_o_bucket != ''
  AND rut_o_bucket != 'Sin Datos';

-- Índice no aplica a vistas; si se necesita mejor rendimiento,
-- considerar materializar o crear índices en calidad_traza.
COMMENT ON VIEW calidad_api_script IS 'Vista de calidad_traza con periodo MM-YYYY para la app TrazaBox';
