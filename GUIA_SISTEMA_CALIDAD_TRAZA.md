# 📘 **GUÍA DEL SISTEMA DE CALIDAD - TRAZA**

## 🎯 **OBJETIVO:**

Gestionar y calcular la **calidad** de los técnicos basándose en las **reiteraciones** de órdenes de trabajo.

---

## 📊 **¿QUÉ ES UNA REITERACIÓN?**

Una **reiteración** ocurre cuando:
1. Un técnico completa una orden de trabajo
2. El mismo cliente tiene otra orden por el mismo problema
3. La segunda orden ocurre dentro de un período específico (generalmente 30 días)

**Ejemplo:**
```
Orden 1: 05/01/26 - Juan Pérez - Reparación Internet
Orden 2: 12/01/26 - Juan Pérez - Reparación Internet (REITERACIÓN)
```

---

## 🗂️ **ESTRUCTURA DEL SISTEMA:**

### **1. Fuente de Datos:**

**API de Kepler:**
```
https://kepler.sbip.cl/api/v1/toa/get_reporte_calidad/centro
```

**Respuesta JSON:**
```json
{
  "data": {
    "data": [
      {
        "access_id": "1-337UL6GA",
        "orden_de_trabajo": "1-3GZVYJJ6",
        "rut_o_bucket": "26494163-6",
        "tecnico": "FS_NFTT_TRAZ_Pedro Aldana D",
        "cliente": "CONFECCIONES ANA...",
        "fecha": "30/12/25",
        "estado": "Completado",
        "tipo_de_actividad": "Reparación",
        "es_reiterado": "NO",
        "dias_diferencia": null,
        "reiterada_por_ot": null
      }
    ],
    "fecha_ejecucion": "2026-02-16 16:21:47",
    "total_registros": 31289,
    "zona": "centro"
  }
}
```

---

### **2. Tabla en Supabase:**

**Nombre:** `calidad_traza`

**Columnas principales:**

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id` | BIGSERIAL | ID auto-incremental |
| `orden_de_trabajo` | TEXT | Número de orden (ej: 1-3GZVYJJ6) |
| `rut_o_bucket` | TEXT | RUT del técnico |
| `tecnico` | TEXT | Nombre del técnico |
| `cliente` | TEXT | Nombre del cliente |
| `fecha` | TEXT | Fecha original (DD/MM/YY) |
| `fecha_completa` | DATE | Fecha parseada |
| `estado` | TEXT | Estado de la orden |
| `tipo_de_actividad` | TEXT | Tipo de actividad |
| `es_reiterado` | TEXT | 'SI' o 'NO' |
| `dias_diferencia` | INTEGER | Días entre orden original y reiteración |
| `reiterada_por_ot` | TEXT | Orden original que generó la reiteración |
| `reiterada_por_tecnico` | TEXT | Técnico de la orden original |

---

### **3. Vistas SQL:**

#### **v_calidad_tecnicos** (Resumen por técnico y mes)

```sql
SELECT * FROM v_calidad_tecnicos
WHERE rut_tecnico = '26402839-6'
  AND mes = 1
  AND anio = 2026;
```

**Columnas:**
- `rut_tecnico` - RUT del técnico
- `tecnico` - Nombre del técnico
- `mes` / `anio` - Período
- `total_ordenes` - Total de órdenes
- `ordenes_completadas` - Órdenes completadas
- `ordenes_reiteradas` - Órdenes que son reiteraciones
- `ordenes_no_reiteradas` - Órdenes sin reiteración
- `porcentaje_reiteracion` - % de reiteraciones sobre completadas

#### **v_reiteraciones_detalle** (Detalle de cada reiteración)

```sql
SELECT * FROM v_reiteraciones_detalle
WHERE rut_tecnico = '26402839-6'
  AND EXTRACT(MONTH FROM fecha_completa) = 1
  AND EXTRACT(YEAR FROM fecha_completa) = 2026;
```

**Columnas:**
- Todas las columnas de la orden reiterada
- Información de la orden original que causó la reiteración

---

## 🚀 **CÓMO IMPLEMENTAR:**

### **PASO 1: Crear la tabla en Supabase**

1. Abrir Supabase SQL Editor: https://supabase.com/dashboard/project/szoywhtkilgvfrczuyqn/sql
2. Copiar y pegar: `TABLA_CALIDAD_TRAZA.sql`
3. Ejecutar (▶️)
4. Verificar:
   ```sql
   SELECT COUNT(*) FROM calidad_traza;
   ```

### **PASO 2: Configurar AppScript**

1. Abrir Google Apps Script: https://script.google.com
2. Crear nuevo proyecto: "Calidad TRAZA"
3. Copiar y pegar: `APPSCRIPT_CALIDAD_TRAZA.js`
4. Guardar (💾)

### **PASO 3: Ejecutar primera carga**

1. En Apps Script, seleccionar función: `probarExtraccionCalidad`
2. Hacer clic en **Ejecutar** (▶️)
3. Autorizar permisos (primera vez)
4. Ver el log:
   ```
   ✅ Registros obtenidos: 31289
   ✅ Registros insertados: 31289
   ✅ Lotes exitosos: 313/313
   ```

### **PASO 4: Programar ejecución diaria**

1. En Apps Script, hacer clic en el **reloj** ⏰ (Triggers)
2. Agregar trigger:
   - **Función:** `extraerCalidadTRAZA`
   - **Tipo:** Time-driven
   - **Frecuencia:** Day timer
   - **Hora:** 6:00 - 7:00 AM (o la hora que prefieras)
3. Guardar

---

## 📊 **EJEMPLOS DE USO:**

### **Ejemplo 1: Ver calidad de un técnico en Enero**

```sql
SELECT 
    tecnico,
    total_ordenes,
    ordenes_completadas,
    ordenes_reiteradas,
    porcentaje_reiteracion
FROM v_calidad_tecnicos
WHERE rut_tecnico = '26402839-6'
  AND mes = 1
  AND anio = 2026;
```

**Resultado esperado:**
```
tecnico               | total | completadas | reiteradas | porcentaje
----------------------|-------|-------------|------------|------------
Alberto Escalona G    |  120  |     115     |      8     |    6.96%
```

### **Ejemplo 2: Ver todas las reiteraciones de un técnico**

```sql
SELECT 
    fecha,
    orden_de_trabajo,
    cliente,
    tipo_de_actividad,
    dias_diferencia,
    reiterada_por_ot,
    reiterada_por_fecha
FROM v_reiteraciones_detalle
WHERE rut_tecnico = '26402839-6'
  AND EXTRACT(MONTH FROM fecha_completa) = 1
  AND EXTRACT(YEAR FROM fecha_completa) = 2026
ORDER BY fecha_completa DESC;
```

**Resultado esperado:**
```
fecha    | orden        | cliente        | dias_dif | ot_original
---------|--------------|----------------|----------|-------------
15/01/26 | 1-3HDTTRB1   | Juan Pérez     |    7     | 1-3H5USGVU
12/01/26 | 1-3HCDD7HL   | María López    |    5     | 1-3H67K8MS
```

### **Ejemplo 3: Top 10 técnicos con mejor calidad (menos reiteraciones)**

```sql
SELECT 
    tecnico,
    ordenes_completadas,
    ordenes_reiteradas,
    porcentaje_reiteracion
FROM v_calidad_tecnicos
WHERE mes = 1 
  AND anio = 2026
  AND ordenes_completadas > 50  -- Solo técnicos con >50 órdenes
ORDER BY porcentaje_reiteracion ASC
LIMIT 10;
```

### **Ejemplo 4: Top 10 técnicos con peor calidad (más reiteraciones)**

```sql
SELECT 
    tecnico,
    ordenes_completadas,
    ordenes_reiteradas,
    porcentaje_reiteracion
FROM v_calidad_tecnicos
WHERE mes = 1 
  AND anio = 2026
  AND ordenes_completadas > 50  -- Solo técnicos con >50 órdenes
ORDER BY porcentaje_reiteracion DESC
LIMIT 10;
```

### **Ejemplo 5: Estadísticas generales del mes**

```sql
SELECT 
    COUNT(DISTINCT rut_tecnico) AS total_tecnicos,
    SUM(total_ordenes) AS total_ordenes,
    SUM(ordenes_completadas) AS total_completadas,
    SUM(ordenes_reiteradas) AS total_reiteradas,
    ROUND(AVG(porcentaje_reiteracion), 2) AS promedio_reiteracion,
    MIN(porcentaje_reiteracion) AS mejor_calidad,
    MAX(porcentaje_reiteracion) AS peor_calidad
FROM v_calidad_tecnicos
WHERE mes = 1 
  AND anio = 2026;
```

---

## 🔍 **QUERIES ÚTILES PARA DEBUG:**

### **Ver registros más recientes:**

```sql
SELECT *
FROM calidad_traza
ORDER BY created_at DESC
LIMIT 10;
```

### **Ver reiteraciones del día:**

```sql
SELECT 
    fecha,
    rut_o_bucket,
    tecnico,
    orden_de_trabajo,
    cliente,
    reiterada_por_ot
FROM calidad_traza
WHERE es_reiterado = 'SI'
  AND fecha = '14/02/26'
ORDER BY tecnico;
```

### **Ver técnicos sin RUT (para corregir):**

```sql
SELECT 
    DISTINCT tecnico,
    rut_o_bucket
FROM calidad_traza
WHERE rut_o_bucket IS NULL 
   OR rut_o_bucket = '' 
   OR rut_o_bucket = 'Sin Datos'
ORDER BY tecnico;
```

### **Contar órdenes por estado:**

```sql
SELECT 
    estado,
    COUNT(*) AS cantidad,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS porcentaje
FROM calidad_traza
GROUP BY estado
ORDER BY cantidad DESC;
```

---

## 🎯 **INTEGRACIÓN CON LA APP FLUTTER:**

### **Servicio: `calidad_service.dart`**

```dart
class CalidadService {
  static final _supabase = Supabase.instance.client;

  /// Obtener resumen de calidad de un técnico
  static Future<Map<String, dynamic>> obtenerCalidadTecnico(
    String rutTecnico, {
    int? mes,
    int? anno,
  }) async {
    final now = DateTime.now();
    final mesConsulta = mes ?? now.month;
    final annoConsulta = anno ?? now.year;

    final response = await _supabase
        .from('v_calidad_tecnicos')
        .select()
        .eq('rut_tecnico', rutTecnico)
        .eq('mes', mesConsulta)
        .eq('anio', annoConsulta)
        .maybeSingle();

    if (response == null) {
      return {
        'total_ordenes': 0,
        'ordenes_completadas': 0,
        'ordenes_reiteradas': 0,
        'porcentaje_reiteracion': 0.0,
      };
    }

    return {
      'total_ordenes': response['total_ordenes'],
      'ordenes_completadas': response['ordenes_completadas'],
      'ordenes_reiteradas': response['ordenes_reiteradas'],
      'porcentaje_reiteracion': (response['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0,
    };
  }

  /// Obtener detalle de reiteraciones
  static Future<List<Map<String, dynamic>>> obtenerReiteraciones(
    String rutTecnico, {
    int? mes,
    int? anno,
  }) async {
    final now = DateTime.now();
    final mesConsulta = mes ?? now.month;
    final annoConsulta = anno ?? now.year;

    final response = await _supabase
        .from('v_reiteraciones_detalle')
        .select()
        .eq('rut_tecnico', rutTecnico)
        .filter('fecha_completa', 'gte', '$annoConsulta-${mesConsulta.toString().padLeft(2, '0')}-01')
        .filter('fecha_completa', 'lt', '$annoConsulta-${(mesConsulta % 12 + 1).toString().padLeft(2, '0')}-01')
        .order('fecha_completa', ascending: false);

    return List<Map<String, dynamic>>.from(response as List);
  }
}
```

---

## ⚠️ **TROUBLESHOOTING:**

### **Problema 1: No se insertan datos**

**Causa:** Error en la conexión a Supabase o credenciales incorrectas.

**Solución:**
1. Verificar URL y API Key en `CONFIG_CALIDAD`
2. Verificar que la tabla existe:
   ```sql
   SELECT * FROM calidad_traza LIMIT 1;
   ```
3. Revisar logs de Apps Script

### **Problema 2: RUTs vacíos o incorrectos**

**Causa:** El campo `rut_o_bucket` en Kepler viene vacío.

**Solución:**
El AppScript intenta extraer el RUT del campo `tecnico` automáticamente. Si aún hay problemas, ejecutar:
```sql
UPDATE calidad_traza
SET rut_o_bucket = '12345678-9'
WHERE tecnico LIKE '%Pedro Aldana%'
  AND (rut_o_bucket IS NULL OR rut_o_bucket = '');
```

### **Problema 3: Fechas no se parsean**

**Causa:** Formato de fecha incorrecto.

**Solución:**
El trigger `parsear_fecha_calidad()` parsea automáticamente. Si falla, verificar:
```sql
SELECT 
    fecha,
    fecha_completa,
    CASE 
        WHEN fecha_completa IS NULL THEN '❌ No parseada'
        ELSE '✅ OK'
    END AS estado
FROM calidad_traza
WHERE fecha_completa IS NULL
LIMIT 10;
```

---

## 📝 **CHECKLIST DE IMPLEMENTACIÓN:**

- [ ] **PASO 1:** Ejecutar `TABLA_CALIDAD_TRAZA.sql` en Supabase
- [ ] **PASO 2:** Verificar que la tabla se creó: `SELECT COUNT(*) FROM calidad_traza;`
- [ ] **PASO 3:** Crear proyecto en Apps Script
- [ ] **PASO 4:** Copiar código de `APPSCRIPT_CALIDAD_TRAZA.js`
- [ ] **PASO 5:** Ejecutar `probarExtraccionCalidad()` manualmente
- [ ] **PASO 6:** Verificar que se insertaron datos: `SELECT COUNT(*) FROM calidad_traza;`
- [ ] **PASO 7:** Programar trigger diario en Apps Script
- [ ] **PASO 8:** Crear servicio Flutter `calidad_service.dart`
- [ ] **PASO 9:** Integrar en la app (pantalla "Tu Mes" o nueva pantalla)
- [ ] **PASO 10:** Probar en la app con un técnico real

---

## 🎉 **RESULTADO ESPERADO:**

```
┌──────────────────────────────────────┐
│     TU CALIDAD - ENERO 2026          │
├──────────────────────────────────────┤
│                                      │
│  📊 Órdenes completadas: 115         │
│  ⚠️  Reiteraciones: 8                 │
│  ✅ Calidad: 93.04%                  │
│                                      │
│  🎯 Objetivo: >95%                   │
│                                      │
│  📋 Ver detalle de reiteraciones →  │
└──────────────────────────────────────┘
```

---

**🎯 ¡Sistema de calidad listo para implementar!**

