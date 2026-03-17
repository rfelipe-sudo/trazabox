-- ═══════════════════════════════════════════════════════════════════
-- DEBUG: ¿Por qué da 22 días en lugar de 20?
-- ═══════════════════════════════════════════════════════════════════

-- Verificar si existe el festivo 1 de enero
SELECT * FROM festivos_chile WHERE fecha = '2026-01-01';

-- Ver todos los festivos de enero
SELECT * FROM festivos_chile WHERE EXTRACT(MONTH FROM fecha) = 1 AND EXTRACT(YEAR FROM fecha) = 2026;

-- Contar domingos de enero 2026
SELECT 
    'Domingos de Enero 2026' as descripcion,
    COUNT(*) as cantidad
FROM generate_series('2026-01-01'::date, '2026-01-31'::date, '1 day'::interval) as fecha
WHERE EXTRACT(DOW FROM fecha) = 0;

-- Listar todos los domingos
SELECT fecha, TO_CHAR(fecha, 'Day DD') as dia
FROM generate_series('2026-01-01'::date, '2026-01-31'::date, '1 day'::interval) as fecha
WHERE EXTRACT(DOW FROM fecha) = 0
ORDER BY fecha;

-- Verificar cálculo manual
SELECT 
    31 as dias_mes,
    5 as domingos,
    1 as festivos,
    (2 * 5) as descuento_por_domingos,
    31 - (2 * 5) - 1 as dias_operativos_esperados;

-- Probar la función directamente
SELECT calcular_dias_operativos(1, 2026, '5x2') as resultado_funcion;

-- Ver el detalle del cálculo dentro de la función
DO $$
DECLARE
    v_primer_dia DATE := '2026-01-01';
    v_ultimo_dia DATE := '2026-01-31';
    v_dia_actual DATE;
    v_domingos INTEGER := 0;
    v_festivos INTEGER := 0;
    v_dow INTEGER;
BEGIN
    v_dia_actual := v_primer_dia;
    
    RAISE NOTICE 'Analizando Enero 2026...';
    
    WHILE v_dia_actual <= v_ultimo_dia LOOP
        v_dow := EXTRACT(DOW FROM v_dia_actual);
        
        IF v_dow = 0 THEN
            v_domingos := v_domingos + 1;
            RAISE NOTICE 'Domingo %: %', v_domingos, v_dia_actual;
        END IF;
        
        IF EXISTS (SELECT 1 FROM festivos_chile WHERE fecha = v_dia_actual) AND v_dow != 0 THEN
            v_festivos := v_festivos + 1;
            RAISE NOTICE 'Festivo (no domingo): %', v_dia_actual;
        END IF;
        
        v_dia_actual := v_dia_actual + INTERVAL '1 day';
    END LOOP;
    
    RAISE NOTICE '--------------------';
    RAISE NOTICE 'Total domingos: %', v_domingos;
    RAISE NOTICE 'Total festivos (no domingo): %', v_festivos;
    RAISE NOTICE 'Días operativos 5x2: % - (2 × %) - % = %', 31, v_domingos, v_festivos, 31 - (2 * v_domingos) - v_festivos;
END $$;

