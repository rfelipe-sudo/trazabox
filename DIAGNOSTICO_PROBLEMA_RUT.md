# 🔍 DIAGNÓSTICO: Problema con `rut_tecnico` en producción

## 📊 **PROBLEMA DETECTADO**

### **Datos de ENERO 2026:**
- ❌ RUT vacío (`""`): **20 órdenes** (19.75 RGU)
- ❌ RUT = timestamp (`2026-01-09T08:00:00.000Z`): **75 órdenes** (86.25 RGU)
- ✅ **TOTAL**: **95 órdenes** que la app NO encuentra porque busca por `rut_tecnico = '26402839-6'`

### **Datos de FEBRERO 2026:**
- ✅ RUT correcto (`26402839-6`): **87 órdenes** (61.50 RGU) ← **Solo estas las ve la app**
- ❌ RUT vacío: **6 órdenes** (6.00 RGU)
- ❌ RUT = timestamp: **8 órdenes** (12.50 RGU)

---

## 🎯 **CAUSA RAÍZ**

El AppScript está insertando incorrectamente el `rut_tecnico` en la tabla `produccion`:

1. **En algunos registros**: El campo `rut_tecnico` está **VACÍO** (`""`)
2. **En otros registros**: El campo `rut_tecnico` contiene un **TIMESTAMP** (ejemplo: `2026-01-09T08:00:00.000Z`) en lugar del RUT

### **Posibles causas en el AppScript:**

#### **Causa 1: Extracción incorrecta del RUT desde Kepler**
```javascript
// ❌ PROBLEMA: Si el RUT no viene en el campo esperado
const rutTecnico = orden['rut_tecnico'] || orden['fecha_trabajo']; // ERROR: Asigna fecha si no encuentra RUT

// ✅ CORRECTO:
const rutTecnico = orden['rut_tecnico'] || ''; // Dejar vacío si no hay RUT
```

#### **Causa 2: Mapeo incorrecto de columnas**
```javascript
// ❌ PROBLEMA: Si los índices de columnas están mal
const RUT_COL = 5;  // Índice incorrecto
const FECHA_COL = 3;

// Si el RUT está en la columna 3 y la fecha en la 5, 
// entonces está asignando la FECHA al campo rut_tecnico

// ✅ CORRECTO: Verificar los índices correctos en la API de Kepler
```

#### **Causa 3: Conversión de fecha a timestamp**
```javascript
// ❌ PROBLEMA: Si está convirtiendo la fecha a ISO string y asignándola al RUT
const fecha = new Date(orden['fecha_trabajo']);
const rutTecnico = fecha.toISOString(); // ❌ Esto da "2026-01-09T08:00:00.000Z"

// ✅ CORRECTO:
const rutTecnico = orden['rut_tecnico'];
const fecha = orden['fecha_trabajo'];
```

---

## 🔧 **SOLUCIÓN EN 3 PASOS**

### **PASO 1: Corregir los datos existentes (SQL)**
**Archivo**: `FIX_RUTS_ENERO_FEBRERO.sql`

Este script corrige los RUTs incorrectos en la base de datos basándose en el nombre del técnico desde `tecnicos_traza_zc`.

**Ejecutar en Supabase SQL Editor:**
1. Abre el archivo `FIX_RUTS_ENERO_FEBRERO.sql`
2. Copia todo el contenido
3. Pégalo en el SQL Editor de Supabase
4. Ejecuta el script completo
5. Verifica que Alberto Escalona ahora tenga ~95 órdenes en Enero con RUT correcto

---

### **PASO 2: Identificar y corregir el AppScript**

**Necesito que me compartas:**
1. El AppScript completo actual (`APPSCRIPT_TRAZA_FINAL.js`)
2. Un ejemplo de respuesta JSON de la API de Kepler (primeros 2-3 registros)

**Con esto podremos:**
- Identificar qué campo tiene el RUT real
- Corregir el mapeo de columnas
- Asegurar que `rut_tecnico` siempre se cargue correctamente

---

### **PASO 3: Modificar la app (temporal) para buscar por nombre si RUT está vacío**

**Modificación en `produccion_service.dart`:**

```dart
// ANTES (solo busca por RUT):
final response = await _supabase
    .from('produccion')
    .select()
    .eq('rut_tecnico', rutTecnico);

// DESPUÉS (busca por RUT O por nombre):
final response = await _supabase
    .from('produccion')
    .select()
    .or('rut_tecnico.eq.$rutTecnico,tecnico.eq.$nombreTecnico');
```

**Pero esto es solo temporal**. Lo ideal es que el AppScript cargue el RUT correctamente desde el inicio.

---

## ✅ **ORDEN DE EJECUCIÓN**

1. **AHORA**: Ejecuta `FIX_RUTS_ENERO_FEBRERO.sql` para corregir Enero y Febrero
2. **DESPUÉS**: Comparte el AppScript para identificar el problema
3. **FINALMENTE**: Corregimos el AppScript para que los datos futuros se carguen bien

---

## 📝 **VERIFICACIÓN POST-FIX**

Después de ejecutar el SQL, esta consulta debe mostrar ~95 órdenes con el RUT correcto:

```sql
SELECT 
    rut_tecnico,
    COUNT(*) as ordenes,
    ROUND(SUM(rgu_total) FILTER (WHERE estado = 'Completado'), 2) as rgu_total
FROM produccion
WHERE tecnico = 'Alberto Escalona G'
  AND (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
GROUP BY rut_tecnico;
```

**Resultado esperado:**
| rut_tecnico | ordenes | rgu_total |
|-------------|---------|-----------|
| 26402839-6  | 95      | ~106.00   |

---

## 🎯 **PRÓXIMOS PASOS**

1. ✅ Ejecuta el SQL `FIX_RUTS_ENERO_FEBRERO.sql`
2. ✅ Comparte el resultado de la consulta de verificación
3. ✅ Comparte el AppScript actual
4. ✅ Prueba la app con Alberto Escalona (debe ver datos de Enero ahora)

