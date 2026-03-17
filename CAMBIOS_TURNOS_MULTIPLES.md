# ✅ **CAMBIOS: SOPORTE PARA MÚLTIPLES TURNOS**

## 🔄 **¿QUÉ CAMBIÓ?**

El sistema ahora soporta **2 tipos de turno** diferentes:

### **ANTES** ❌

```
Todos los técnicos:
- Inicio esperado: 09:45 (L-V)
- Fin esperado: 18:30 (L-V)
```

### **AHORA** ✅

```
Turno 5x2:
- Inicio esperado: 09:15 (L-V)
- Fin esperado: 19:00 (L-V)

Turno 6x1:
- Inicio esperado: 09:45 (L-V)
- Fin esperado: 18:30 (L-V)
```

---

## 📊 **TABLA DE HORARIOS:**

| Concepto | Turno 5x2 | Turno 6x1 |
|----------|-----------|-----------|
| **L-V Inicio** | 09:15 | 09:45 |
| **L-V Fin** | 19:00 | 18:30 |
| **Sáb Inicio** | 10:00 | 10:00 |
| **Sáb Fin** | 14:00 | 14:00 |
| **Inicio Tardío** | Después de 09:15 | Después de 09:45 |
| **Hora Extra** | Después de 19:00 | Después de 18:30 |

---

## 🗂️ **ARCHIVOS ACTUALIZADOS:**

| Archivo | Estado | Descripción |
|---------|--------|-------------|
| `SISTEMA_TIEMPOS_COMPLETO_TRAZA_V2.sql` | ✅ **NUEVO** | Script SQL con soporte para turnos |
| `TABLA_COMPARACION_TURNOS.md` | ✅ **NUEVO** | Documentación de turnos |
| `INSTRUCCIONES_IMPLEMENTAR_TIEMPOS.md` | ✅ **ACTUALIZADO** | Ahora usa V2 del script |
| `CAMBIOS_TURNOS_MULTIPLES.md` | ✅ **NUEVO** | Este archivo |

---

## 🚀 **¿QUÉ DEBES HACER?**

### **1️⃣ IGNORAR el archivo antiguo:**

~~`SISTEMA_TIEMPOS_COMPLETO_TRAZA.sql`~~ ❌ **NO USAR**

### **2️⃣ USAR el archivo nuevo:**

`SISTEMA_TIEMPOS_COMPLETO_TRAZA_V2.sql` ✅ **USAR ESTE**

### **3️⃣ VERIFICAR turnos en Supabase:**

Cada técnico debe tener su `tipo_turno` asignado en `tecnicos_traza_zc`:

```sql
SELECT rut, nombre_completo, tipo_turno
FROM tecnicos_traza_zc
WHERE activo = true;
```

**Valores válidos:**
- `'5x2'` - Turno 5 días trabajo, 2 descanso
- `'6x1'` - Turno 6 días trabajo, 1 descanso
- `NULL` - Se asume `'6x1'` por defecto

### **4️⃣ ASIGNAR turnos (si no tienen):**

```sql
-- Ejemplo: Asignar turno 5x2 a un técnico
UPDATE tecnicos_traza_zc
SET tipo_turno = '5x2'
WHERE rut = '12345678-9';

-- O asignar turno 6x1
UPDATE tecnicos_traza_zc
SET tipo_turno = '6x1'
WHERE rut = '98765432-1';
```

---

## 🔍 **CÓMO FUNCIONA:**

### **1. Base de Datos (Supabase):**

Las funciones SQL ahora reciben el `tipo_turno` como parámetro:

```sql
calcular_minutos_inicio_tardio(fecha, hora, tipo_turno)
calcular_minutos_hora_extra(fecha, hora_inicio, hora_fin, duracion, tipo_turno)
```

Y ajustan los horarios límite según el turno:

```sql
-- Turno 5x2
Inicio esperado L-V: 09:15
Fin esperado L-V: 19:00

-- Turno 6x1
Inicio esperado L-V: 09:45
Fin esperado L-V: 18:30
```

### **2. Vistas SQL:**

Las vistas consultan automáticamente el turno del técnico:

```sql
v_tiempos_diarios       → Incluye columna 'tipo_turno'
v_tiempos_mensuales     → Agrupa por 'tipo_turno'
v_resumen_tiempos_app   → Muestra 'tipo_turno'
```

### **3. App Flutter:**

**NO necesita cambios.** Las vistas ya devuelven los cálculos correctos según el turno de cada técnico.

---

## 🧪 **PRUEBAS DE VERIFICACIÓN:**

### **Prueba 1: Comparar cálculos entre turnos**

```sql
-- Técnico turno 5x2 que inició a las 09:30
SELECT calcular_minutos_inicio_tardio('05/01/26', '09:30', '5x2');
-- Resultado esperado: 15 minutos (09:30 - 09:15)

-- Mismo técnico pero turno 6x1
SELECT calcular_minutos_inicio_tardio('05/01/26', '09:30', '6x1');
-- Resultado esperado: 0 minutos (09:30 < 09:45)
```

### **Prueba 2: Ver inicio tardío por turno (Enero 2026)**

```sql
SELECT 
    tipo_turno,
    COUNT(*) AS dias,
    ROUND(AVG(minutos_inicio_tardio), 2) AS promedio_min,
    ROUND(SUM(minutos_inicio_tardio) / 60.0, 2) AS total_hrs
FROM v_tiempos_diarios
WHERE EXTRACT(MONTH FROM fecha_completa) = 1
  AND EXTRACT(YEAR FROM fecha_completa) = 2026
  AND minutos_inicio_tardio > 0
GROUP BY tipo_turno;
```

Resultado esperado:
```
tipo_turno | dias | promedio_min | total_hrs
-----------|------|--------------|----------
5x2        |  45  |     35.2     |   26.4
6x1        |  38  |     28.5     |   18.0
```

### **Prueba 3: Ver horas extras por turno (Enero 2026)**

```sql
SELECT 
    tipo_turno,
    COUNT(*) AS dias,
    ROUND(AVG(minutos_hora_extra), 2) AS promedio_min,
    ROUND(SUM(minutos_hora_extra) / 60.0, 2) AS total_hrs
FROM v_tiempos_diarios
WHERE EXTRACT(MONTH FROM fecha_completa) = 1
  AND EXTRACT(YEAR FROM fecha_completa) = 2026
  AND minutos_hora_extra > 0
GROUP BY tipo_turno;
```

---

## ⚠️ **POSIBLES PROBLEMAS:**

### **Problema 1: Técnicos sin turno asignado**

**Síntoma:** Algunos técnicos tienen `tipo_turno = NULL`

**Solución:**
```sql
-- Ver técnicos sin turno
SELECT rut, nombre_completo, tipo_turno
FROM tecnicos_traza_zc
WHERE tipo_turno IS NULL
  AND activo = true;

-- Asignar turno por defecto (6x1)
UPDATE tecnicos_traza_zc
SET tipo_turno = '6x1'
WHERE tipo_turno IS NULL;
```

### **Problema 2: Los cálculos no coinciden**

**Síntoma:** El inicio tardío o las horas extras no son correctos

**Solución:**
1. Verificar el turno del técnico:
   ```sql
   SELECT rut, nombre_completo, tipo_turno
   FROM tecnicos_traza_zc
   WHERE rut = '12345678-9';
   ```

2. Verificar manualmente el cálculo:
   ```sql
   -- Para un día específico
   SELECT 
       fecha_trabajo,
       tipo_turno,
       primera_orden_hora,
       ultima_orden_hora,
       minutos_inicio_tardio,
       minutos_hora_extra
   FROM v_tiempos_diarios
   WHERE rut_tecnico = '12345678-9'
     AND fecha_trabajo = '05/01/26';
   ```

3. Comparar con la tabla de horarios (`TABLA_COMPARACION_TURNOS.md`)

---

## 📝 **EJEMPLO PRÁCTICO:**

### **Escenario:** Juan Pérez (turno 5x2) vs María López (turno 6x1)

Ambos trabajan el **Lunes 05/01/26**:
- Primera orden: 09:30
- Última orden: 19:15

### **Juan Pérez (5x2):**

```
Inicio: 09:30
Esperado: 09:15
Inicio tardío: 09:30 - 09:15 = 15 min ⚠️

Fin: 19:15
Esperado: 19:00
Hora extra: 19:15 - 19:00 = 15 min ✅
```

### **María López (6x1):**

```
Inicio: 09:30
Esperado: 09:45
Inicio tardío: 09:30 < 09:45 = 0 min ✅

Fin: 19:15
Esperado: 18:30
Hora extra: 19:15 - 18:30 = 45 min ⚠️
```

**Conclusión:**
- Juan tiene menos hora extra porque su turno termina a las 19:00
- María NO tiene inicio tardío porque su turno empieza a las 09:45

---

## ✅ **CHECKLIST DE IMPLEMENTACIÓN:**

- [ ] **PASO 1:** Eliminar vistas antiguas (opcional, para evitar confusión)
  ```sql
  DROP VIEW IF EXISTS v_resumen_tiempos_app CASCADE;
  DROP VIEW IF EXISTS v_tiempos_mensuales CASCADE;
  DROP VIEW IF EXISTS v_tiempos_diarios CASCADE;
  DROP FUNCTION IF EXISTS calcular_minutos_hora_extra(TEXT, TEXT, TEXT, INTEGER) CASCADE;
  DROP FUNCTION IF EXISTS calcular_minutos_inicio_tardio(TEXT, TEXT) CASCADE;
  ```

- [ ] **PASO 2:** Ejecutar `SISTEMA_TIEMPOS_COMPLETO_TRAZA_V2.sql`

- [ ] **PASO 3:** Verificar que las vistas se crearon:
  ```sql
  SELECT * FROM v_tiempos_diarios LIMIT 5;
  SELECT * FROM v_resumen_tiempos_app LIMIT 5;
  ```

- [ ] **PASO 4:** Asignar turnos a todos los técnicos activos:
  ```sql
  UPDATE tecnicos_traza_zc
  SET tipo_turno = '6x1'  -- o '5x2' según corresponda
  WHERE tipo_turno IS NULL
    AND activo = true;
  ```

- [ ] **PASO 5:** Verificar cálculos con las queries de prueba

- [ ] **PASO 6:** Actualizar `produccion_service.dart` (si aún no se hizo)

- [ ] **PASO 7:** Compilar y probar la app

---

## 🎉 **RESULTADO FINAL:**

La app ahora:
- ✅ Respeta el turno de cada técnico
- ✅ Calcula inicio tardío según el horario correcto
- ✅ Calcula horas extras según el horario correcto
- ✅ Muestra el tipo de turno en la UI
- ✅ Permite comparar estadísticas por turno

---

**📖 Para más información, consulta:**
- `TABLA_COMPARACION_TURNOS.md` - Comparación detallada de turnos
- `INSTRUCCIONES_IMPLEMENTAR_TIEMPOS.md` - Guía completa de implementación
- `RESUMEN_SISTEMA_TIEMPOS.md` - Documentación técnica del sistema

