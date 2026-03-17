# ✅ VERIFICACIÓN APPSCRIPT TRAZA

## 📋 Estado actual del AppScript

Tu script está **correctamente configurado**:

- ✅ **API Kepler:** `https://kepler.sbip.cl/api/v1/toa/get_sabana_filtrada/metro/TRAZ`
- ✅ **Supabase:** `qbryjrkzhvkxusjtwhra` (proyecto TRAZA)
- ✅ **Tabla:** `produccion_traza`
- ✅ **Lógica RGU:** Completa (1 Play, 2 Play, 3 Play, Modificaciones, etc.)

---

## 🚀 PASOS PARA ACTIVAR

### **Paso 1: Verificar que la tabla existe**

Ejecuta en Supabase TRAZA (SQL Editor):

```sql
-- Ver estructura de la tabla
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'produccion_traza'
ORDER BY ordinal_position;
```

### **Paso 2: Ejecutar el AppScript manualmente**

En Google Apps Script:

1. Abre el proyecto del AppScript
2. Selecciona la función: `pruebaProduccionTRAZA`
3. Click en **▶ Ejecutar**
4. Revisa los logs (Ver → Registros)

Deberías ver algo como:
```
🚀 Iniciando extracción de producción TRAZA...
📊 Registros descargados: XXX
✅ Registros procesados: XXX
📈 RGU Total: XXX.XX
💾 Registros guardados en Supabase: XXX
```

### **Paso 3: Verificar datos en Supabase**

```sql
-- Contar registros importados
SELECT COUNT(*) as total FROM produccion_traza;

-- Ver técnicos TRAZA únicos
SELECT 
    rut_tecnico,
    tecnico,
    COUNT(*) as ordenes,
    ROUND(SUM(rgu_total)::numeric, 2) as total_rgu
FROM produccion_traza
WHERE estado = 'Completado'
GROUP BY rut_tecnico, tecnico
ORDER BY total_rgu DESC
LIMIT 10;

-- Ver producción de hoy
SELECT 
    rut_tecnico,
    tecnico,
    COUNT(*) as ordenes,
    ROUND(SUM(rgu_total)::numeric, 2) as rgu_hoy
FROM produccion_traza
WHERE fecha_trabajo = '04/02/26'  -- Ajustar a la fecha actual
  AND estado = 'Completado'
GROUP BY rut_tecnico, tecnico;
```

### **Paso 4: Configurar ejecución automática**

Una vez que confirmes que funciona manualmente:

```javascript
// En Apps Script, ejecuta:
configurarTriggerTRAZA()
// O para horario laboral:
configurarTriggerHorarioLaboral()
```

Esto configurará el script para ejecutarse automáticamente cada 15 minutos (o cada 30 min en horario laboral).

---

## 🔍 DIFERENCIAS ENTRE SCRIPT Y APP

### Campos que guarda el AppScript:

El script guarda estos campos:
- `orden_trabajo`
- `fecha_trabajo` ✅
- `tecnico` ✅
- `codigo_tecnico`
- `rut_tecnico` ✅
- `tipo_actividad`
- `subtipo`
- `tipo_orden` ✅
- `estado` ✅
- `rgu_base`
- `rgu_adicional`
- `rgu_total` ✅
- `cant_dbox`
- `cant_extensores`
- ... y más

### Campos que espera la app (tabla produccion_traza):

Según `SISTEMA_BONOS_TRAZA_COMPLETO.sql`:
- `rut_tecnico` ✅
- `tecnico` ✅
- `fecha_trabajo` ✅
- `orden_trabajo` ✅
- `tipo_orden` ✅
- `tecnologia` ⚠️ **FALTA EN APPSCRIPT**
- `puntos_rgu` ✅ (el script usa `rgu_total`)
- `estado` ✅
- `cliente`
- `direccion`
- `comuna`
- `region`

---

## ⚠️ AJUSTE NECESARIO: Campo `tecnologia`

El AppScript actual **NO está detectando la tecnología (FTTH/NTT/HFC)**.

### Solución: Agregar detección de tecnología

Agrega esta función al AppScript:

```javascript
// Agregar después de la función determinarTipoOrden()
function detectarTecnologia(tipoRed) {
  const tipo = (tipoRed || "").toUpperCase();
  
  if (tipo.includes("FTTH") || tipo.includes("GPON")) {
    return "FTTH";
  } else if (tipo.includes("NTT") || tipo.includes("NEUTRO") || tipo.includes("NEUTRAL")) {
    return "NTT";
  } else if (tipo.includes("HFC") || tipo.includes("COAX") || tipo.includes("DOCSIS")) {
    return "HFC";
  }
  
  // Por defecto, si no se detecta, asumir FTTH
  return "FTTH";
}
```

Y en la función `extraerProduccionTRAZA()`, agrega:

```javascript
// Después de la línea: const direccion = ...
const tecnologia = detectarTecnologia(tipoRed);

// Y en el objeto produccion.push(), agrega:
tecnologia: tecnologia,
```

---

## 🔄 MAPEO DE COLUMNAS

Si ya ejecutaste el script y hay datos, necesitamos mapear:

```sql
-- Agregar columna tecnologia si no existe
ALTER TABLE produccion_traza 
ADD COLUMN IF NOT EXISTS tecnologia VARCHAR(20);

-- Actualizar registros existentes
-- Por ahora, asumir FTTH para todos (puedes ajustar después)
UPDATE produccion_traza 
SET tecnologia = 'FTTH'
WHERE tecnologia IS NULL;

-- Mapear rgu_total a puntos_rgu si la columna existe
-- (Verificar primero qué columna usa la tabla)
```

---

## ✅ CHECKLIST

- [ ] AppScript ejecutado manualmente con éxito
- [ ] Datos visibles en Supabase tabla `produccion_traza`
- [ ] Campo `tecnologia` agregado y detectado
- [ ] Trigger automático configurado
- [ ] Verificado que hay técnicos con RUT válido
- [ ] Probado login en la app con un técnico real
- [ ] Abierto "Tu Mes" y verificado que muestra datos

---

## 🎯 Siguiente paso

**¿Ya ejecutaste el AppScript y tienes datos en Supabase?**

Si es así, dame un RUT de un técnico real que aparezca en los datos para que puedas probar el login.

```sql
-- Obtener un técnico real con datos
SELECT rut_tecnico, tecnico, COUNT(*) as ordenes
FROM produccion_traza
WHERE fecha_trabajo LIKE '%/02/26'
  AND estado = 'Completado'
GROUP BY rut_tecnico, tecnico
ORDER BY ordenes DESC
LIMIT 5;
```

Copia el RUT y nombre de un técnico y úsalo para registrarte en la app.

