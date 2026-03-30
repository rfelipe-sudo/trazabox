-- ═══════════════════════════════════════════════════════════════════
-- TABLA horas_extras
-- Almacena las horas extras por orden de trabajo.
-- La app TrazaBox consulta esta tabla para mostrar el detalle de
-- horas extras con la orden de trabajo donde se ejecutaron.
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS horas_extras (
    id BIGSERIAL PRIMARY KEY,
    rut_tecnico VARCHAR(20) NOT NULL,
    orden_trabajo VARCHAR(50) NOT NULL,
    fecha_trabajo VARCHAR(20) NOT NULL,  -- DD/MM/YY o DD/MM/YYYY
    minutos INTEGER NOT NULL DEFAULT 0,  -- minutos de hora extra
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índices para consultas por técnico y mes
CREATE INDEX IF NOT EXISTS idx_horas_extras_rut ON horas_extras(rut_tecnico);
CREATE INDEX IF NOT EXISTS idx_horas_extras_fecha ON horas_extras(fecha_trabajo);

COMMENT ON TABLE horas_extras IS 'Horas extras por orden de trabajo para TrazaBox';
