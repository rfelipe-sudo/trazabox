# ⚡ **PASOS RÁPIDOS - SISTEMA DE CALIDAD**

## 📦 **ARCHIVOS CREADOS:**

1. ✅ `TABLA_CALIDAD_TRAZA.sql` - Ejecutar en Supabase
2. ✅ `APPSCRIPT_CALIDAD_TRAZA.js` - Copiar a Google Apps Script
3. ✅ `GUIA_SISTEMA_CALIDAD_TRAZA.md` - Documentación completa
4. ✅ `RESUMEN_SISTEMA_CALIDAD.md` - Resumen ejecutivo

---

## 🚀 **IMPLEMENTACIÓN EN 4 PASOS:**

### **1️⃣ SUPABASE** (5 min)

```bash
# 1. Abrir:
https://supabase.com/dashboard/project/szoywhtkilgvfrczuyqn/sql

# 2. Copiar todo el contenido de:
TABLA_CALIDAD_TRAZA.sql

# 3. Pegar y ejecutar ▶️

# 4. Verificar:
SELECT COUNT(*) FROM calidad_traza;
```

---

### **2️⃣ APPS SCRIPT** (10 min)

```bash
# 1. Abrir:
https://script.google.com

# 2. Nuevo proyecto: "Calidad TRAZA"

# 3. Copiar todo el contenido de:
APPSCRIPT_CALIDAD_TRAZA.js

# 4. Pegar y guardar 💾
```

---

### **3️⃣ PRIMERA CARGA** (5-10 min)

```bash
# En Apps Script:
# 1. Seleccionar: probarExtraccionCalidad
# 2. Ejecutar ▶️
# 3. Autorizar permisos
# 4. Esperar a que termine (~5 min)
# 5. Ver log: debe decir "✅ PROCESO COMPLETADO"
```

**Verificar en Supabase:**
```sql
-- Debe retornar ~31,000 registros
SELECT COUNT(*) FROM calidad_traza;

-- Ver últimos registros
SELECT * FROM calidad_traza 
ORDER BY created_at DESC 
LIMIT 10;
```

---

### **4️⃣ PROGRAMAR DIARIO** (2 min)

```bash
# En Apps Script:
# 1. Clic en reloj ⏰ (Triggers)
# 2. Agregar trigger:
#    - Función: extraerCalidadTRAZA
#    - Tipo: Time-driven
#    - Frecuencia: Day timer
#    - Hora: 6:00 - 7:00 AM
# 3. Guardar
```

---

## ✅ **VERIFICACIÓN:**

### **Query de prueba:**

```sql
-- Ver técnicos con su calidad en Febrero 2026
SELECT 
    tecnico,
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
tecnico               | completadas | reiteradas | porcentaje
----------------------|-------------|------------|------------
Pedro Aldana D        |     125     |      3     |    2.40%
Nicolas Vivanco L     |     140     |      7     |    5.00%
Luis Castillo Fuentes |     132     |      9     |    6.82%
```

---

## 🎯 **ENDPOINT USADO:**

```
https://kepler.sbip.cl/api/v1/toa/get_reporte_calidad/centro
```

**Datos que trae:**
- ✅ Órdenes de trabajo
- ✅ Si es reiteración (SI/NO)
- ✅ Orden original
- ✅ Días entre órdenes
- ✅ RUT del técnico
- ✅ Cliente afectado

---

## 📊 **VISTA PRINCIPAL:**

**Nombre:** `v_calidad_tecnicos`

**Columnas:**
- `rut_tecnico` - RUT del técnico
- `tecnico` - Nombre
- `mes` / `anio` - Período
- `total_ordenes` - Total
- `ordenes_completadas` - Completadas
- `ordenes_reiteradas` - Reiteraciones
- `porcentaje_reiteracion` ← **MÉTRICA CLAVE**

---

## 💡 **PRÓXIMO PASO:**

Integrar en la app Flutter:
1. Crear servicio `calidad_service.dart`
2. Añadir tarjeta en "Tu Mes"
3. Mostrar: % de calidad y reiteraciones

**Ver:** `GUIA_SISTEMA_CALIDAD_TRAZA.md` (sección "Integración con Flutter")

---

**🎉 ¡Sistema de calidad listo!**

**Tiempo total:** ~25 minutos

