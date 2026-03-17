# ✅ **SISTEMA DE CALIDAD TRAZA - RESUMEN EJECUTIVO**

## 🎯 **QUÉ SE CREÓ:**

Un sistema completo para gestionar y calcular la **calidad** de los técnicos basándose en las **reiteraciones** de órdenes de trabajo.

---

## 📦 **ARCHIVOS CREADOS:**

| Archivo | Tipo | Descripción |
|---------|------|-------------|
| `TABLA_CALIDAD_TRAZA.sql` | 📄 SQL | Script para crear tabla y vistas en Supabase |
| `APPSCRIPT_CALIDAD_TRAZA.js` | 💻 JavaScript | Script para extraer datos de Kepler |
| `GUIA_SISTEMA_CALIDAD_TRAZA.md` | 📘 Documentación | Guía completa del sistema |
| `RESUMEN_SISTEMA_CALIDAD.md` | 📋 Resumen | Este archivo |

---

## 🔄 **FLUJO DE DATOS:**

```
┌─────────────────┐
│     KEPLER      │ ← API: get_reporte_calidad/centro
│ (Centro de Zona)│
└────────┬────────┘
         │
         ▼ (Apps Script diario, 6:00 AM)
┌─────────────────────────────────┐
│  SUPABASE: tabla calidad_traza  │
│                                 │
│  Columnas principales:          │
│  - orden_de_trabajo             │
│  - rut_o_bucket (técnico)       │
│  - fecha                        │
│  - es_reiterado (SI/NO)         │
│  - reiterada_por_ot             │
│  - dias_diferencia              │
└────────┬────────────────────────┘
         │
         ▼ (Vistas SQL automáticas)
┌──────────────────────────────────┐
│  v_calidad_tecnicos              │
│  (resumen por técnico y mes)     │
│                                  │
│  - total_ordenes                 │
│  - ordenes_completadas           │
│  - ordenes_reiteradas            │
│  - porcentaje_reiteracion        │
└────────┬─────────────────────────┘
         │
         ▼ (consulta desde Flutter)
┌──────────────────────────────────┐
│  CalidadService                  │
│  obtenerCalidadTecnico()         │
└────────┬─────────────────────────┘
         │
         ▼ (renderiza)
┌──────────────────────────────────┐
│  App TrazaBox                    │
│  Pantalla "Tu Mes" o nueva       │
└──────────────────────────────────┘
```

---

## 📊 **DATOS CLAVE:**

### **Endpoint de Kepler:**

```
https://kepler.sbip.cl/api/v1/toa/get_reporte_calidad/centro
```

**Datos que trae:**
- ✅ ~31,000 registros de órdenes
- ✅ Estado de cada orden
- ✅ Si es reiteración o no
- ✅ Orden original que causó la reiteración
- ✅ Días entre la orden original y la reiteración
- ✅ RUT del técnico
- ✅ Nombre del técnico
- ✅ Cliente afectado

### **Tabla en Supabase:**

**Nombre:** `calidad_traza`

**Registros esperados:** ~31,000 (depende de la zona)

**Actualización:** Diaria (6:00 AM automático)

### **Vistas SQL:**

1. **`v_calidad_tecnicos`** - Resumen por técnico y mes
   - Total de órdenes
   - Órdenes completadas
   - Órdenes reiteradas
   - **Porcentaje de reiteración** ← MÉTRICA PRINCIPAL

2. **`v_reiteraciones_detalle`** - Detalle de cada reiteración
   - Fecha
   - Orden de trabajo
   - Cliente
   - Orden original
   - Días entre órdenes

---

## 🚀 **PASOS DE IMPLEMENTACIÓN:**

### **1️⃣ CREAR TABLA EN SUPABASE** (5 min)

```bash
# Abrir Supabase SQL Editor
https://supabase.com/dashboard/project/szoywhtkilgvfrczuyqn/sql

# Copiar y pegar contenido de:
TABLA_CALIDAD_TRAZA.sql

# Ejecutar ▶️

# Verificar:
SELECT COUNT(*) FROM calidad_traza; -- Debe retornar 0
```

---

### **2️⃣ CONFIGURAR APPSCRIPT** (10 min)

```bash
# Abrir Google Apps Script
https://script.google.com

# Crear nuevo proyecto: "Calidad TRAZA"

# Copiar y pegar contenido de:
APPSCRIPT_CALIDAD_TRAZA.js

# Guardar 💾
```

**Configuración importante:**
```javascript
const CONFIG_CALIDAD = {
  URL_API: "https://kepler.sbip.cl/api/v1/toa/get_reporte_calidad/centro",
  SUPABASE_URL: "https://szoywhtkilgvfrczuyqn.supabase.co",
  SUPABASE_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  TABLA: "calidad_traza",
};
```

---

### **3️⃣ PRIMERA CARGA MANUAL** (5-10 min)

```bash
# En Apps Script:
# 1. Seleccionar función: probarExtraccionCalidad
# 2. Hacer clic en Ejecutar ▶️
# 3. Autorizar permisos (primera vez)
# 4. Esperar a que termine (~5 min)
# 5. Revisar logs:
```

**Logs esperados:**
```
✅ Registros obtenidos: 31289
✅ Registros válidos: 31000
✅ Registros insertados: 31000
✅ Lotes exitosos: 310/310
⏱️ Duración: 245.67 segundos
```

**Verificar en Supabase:**
```sql
SELECT COUNT(*) FROM calidad_traza;
-- Debe retornar ~31,000

SELECT * FROM calidad_traza LIMIT 5;
-- Debe mostrar registros
```

---

### **4️⃣ PROGRAMAR EJECUCIÓN DIARIA** (2 min)

```bash
# En Apps Script:
# 1. Hacer clic en el reloj ⏰ (Triggers)
# 2. Agregar trigger:
#    - Función: extraerCalidadTRAZA
#    - Tipo: Time-driven
#    - Frecuencia: Day timer
#    - Hora: 6:00 - 7:00 AM
# 3. Guardar
```

---

### **5️⃣ VERIFICAR DATOS** (5 min)

```sql
-- Verificar calidad de un técnico en Febrero 2026
SELECT 
    tecnico,
    total_ordenes,
    ordenes_completadas,
    ordenes_reiteradas,
    porcentaje_reiteracion
FROM v_calidad_tecnicos
WHERE mes = 2
  AND anio = 2026
ORDER BY porcentaje_reiteracion ASC
LIMIT 10;
```

**Resultado esperado:**
```
tecnico               | total | completadas | reiteradas | porcentaje
----------------------|-------|-------------|------------|------------
Pedro Aldana D        |  130  |     125     |      3     |    2.40%
Nicolas Vivanco L     |  145  |     140     |      7     |    5.00%
Luis Castro Torres    |  120  |     115     |      8     |    6.96%
```

---

## 📊 **MÉTRICAS PRINCIPALES:**

### **Porcentaje de Reiteración:**

```
Porcentaje = (Órdenes Reiteradas / Órdenes Completadas) × 100
```

**Escala de calidad:**
- ✅ **Excelente:** 0% - 5%
- 🟡 **Bueno:** 5% - 10%
- ⚠️ **Regular:** 10% - 15%
- ❌ **Malo:** >15%

### **Ejemplo de cálculo:**

```
Técnico: Juan Pérez
Mes: Enero 2026

Total de órdenes: 120
Órdenes completadas: 115
Órdenes reiteradas: 8

Porcentaje de reiteración = (8 / 115) × 100 = 6.96%
Clasificación: 🟡 Bueno
```

---

## 🔍 **QUERIES ÚTILES:**

### **Top 10 mejores técnicos (menos reiteraciones):**

```sql
SELECT 
    tecnico,
    ordenes_completadas,
    ordenes_reiteradas,
    porcentaje_reiteracion
FROM v_calidad_tecnicos
WHERE mes = 2 
  AND anio = 2026
  AND ordenes_completadas > 50
ORDER BY porcentaje_reiteracion ASC
LIMIT 10;
```

### **Top 10 peores técnicos (más reiteraciones):**

```sql
SELECT 
    tecnico,
    ordenes_completadas,
    ordenes_reiteradas,
    porcentaje_reiteracion
FROM v_calidad_tecnicos
WHERE mes = 2 
  AND anio = 2026
  AND ordenes_completadas > 50
ORDER BY porcentaje_reiteracion DESC
LIMIT 10;
```

### **Ver detalle de reiteraciones de un técnico:**

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
  AND EXTRACT(MONTH FROM fecha_completa) = 2
  AND EXTRACT(YEAR FROM fecha_completa) = 2026
ORDER BY fecha_completa DESC;
```

---

## 🎨 **INTEGRACIÓN EN LA APP:**

### **Opción A: Añadir en "Tu Mes"** (recomendado)

Agregar una nueva tarjeta después de "Horas Extras":

```dart
┌──────────────────────────────────────┐
│         Febrero 2026                 │
│                                      │
│           6.14                       │
│         RGU/día                      │
│                                      │
│ ⏰ Inicio tardío: 120m               │
│ ⏳ Horas extras: 540m                 │
│                                      │
│ 📊 TU CALIDAD                        │  ← NUEVO
│ ✅ 93.04% | 8 reiteraciones         │
│ 115 órdenes completadas              │
│ Ver detalle →                        │
└──────────────────────────────────────┘
```

### **Opción B: Nueva pantalla "Calidad"**

Crear una pantalla dedicada con:
- Porcentaje de calidad del mes
- Lista de reiteraciones
- Comparación con otros técnicos
- Gráfico de evolución mensual

---

## ⚠️ **NOTAS IMPORTANTES:**

### **1. Validación de RUTs:**

El AppScript intenta extraer el RUT del campo `tecnico` si `rut_o_bucket` está vacío.

**Formato esperado:**
```
"FS_NFTT_TRAZ_26402839-6_Pedro Aldana D"
        └─────────┬─────────┘
              RUT extraído
```

### **2. Parseo de fechas:**

Las fechas vienen en formato `DD/MM/YY`:
- `30/12/25` → `2025-12-30`
- `14/02/26` → `2026-02-14`

El trigger SQL `parsear_fecha_calidad()` convierte automáticamente.

### **3. Duplicados:**

La tabla tiene constraint `UNIQUE (orden_de_trabajo, fecha)` para evitar duplicados.

Si se ejecuta el AppScript dos veces el mismo día, los registros duplicados se ignoran automáticamente.

---

## ✅ **CHECKLIST FINAL:**

- [ ] Tabla `calidad_traza` creada en Supabase
- [ ] Vistas `v_calidad_tecnicos` y `v_reiteraciones_detalle` creadas
- [ ] AppScript configurado con credenciales correctas
- [ ] Primera carga manual ejecutada exitosamente
- [ ] Datos verificados en Supabase (>30,000 registros)
- [ ] Trigger diario programado en Apps Script
- [ ] Queries de prueba funcionando correctamente
- [ ] Servicio Flutter `calidad_service.dart` creado (pendiente)
- [ ] UI integrada en la app (pendiente)

---

## 🎯 **PRÓXIMOS PASOS:**

### **CORTO PLAZO** (esta semana):
1. ✅ Crear tabla y cargar datos históricos
2. ✅ Programar carga diaria
3. ⏳ Crear servicio Flutter
4. ⏳ Integrar en la app

### **MEDIANO PLAZO** (próximas semanas):
- [ ] Dashboard web de calidad
- [ ] Alertas automáticas por exceso de reiteraciones
- [ ] Reportes mensuales automatizados
- [ ] Análisis de causas de reiteraciones

### **LARGO PLAZO** (futuro):
- [ ] Sistema de bonificación por calidad
- [ ] Predicción de reiteraciones con ML
- [ ] Integración con sistema de pagos

---

## 📚 **DOCUMENTACIÓN COMPLETA:**

- 📘 **`GUIA_SISTEMA_CALIDAD_TRAZA.md`** - Guía técnica completa
- 📄 **`TABLA_CALIDAD_TRAZA.sql`** - Script SQL con comentarios
- 💻 **`APPSCRIPT_CALIDAD_TRAZA.js`** - Código Apps Script documentado
- 📋 **`RESUMEN_SISTEMA_CALIDAD.md`** - Este archivo

---

## 🎉 **RESULTADO FINAL:**

Un sistema completo y automático que:
- ✅ Extrae datos de Kepler diariamente
- ✅ Almacena en Supabase organizadamente
- ✅ Calcula porcentajes de reiteración
- ✅ Genera vistas optimizadas para la app
- ✅ Permite análisis detallado por técnico
- ✅ Listo para integrar en TrazaBox

---

**¿Listo para ejecutar?** 🚀

**Total de tiempo estimado:** ~30 minutos

