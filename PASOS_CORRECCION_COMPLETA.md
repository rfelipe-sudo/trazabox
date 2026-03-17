# 🔧 CORRECCIÓN COMPLETA: Problema de RUTs en Producción

## 📋 **RESUMEN DEL PROBLEMA**

### **ENERO 2026:**
- ❌ RUT vacío: 20 órdenes
- ❌ RUT = timestamp: 75 órdenes
- **Total no visible en la app**: **95 órdenes** de Alberto Escalona

### **FEBRERO 2026:**
- ✅ RUT correcto: 87 órdenes (solo estas se ven)
- ❌ RUT vacío/timestamp: 14 órdenes

### **CAUSA RAÍZ:**
El AppScript estaba usando el campo `"Rut o Bucket"` de Kepler (que es el RUT del cliente), en lugar de extraer el RUT del técnico desde el campo `"Técnico"`.

---

## ✅ **SOLUCIÓN EN 3 PASOS**

### **PASO 1️⃣: Corregir los datos de Enero y Febrero (SQL)**

**Archivo**: `FIX_RUTS_ENERO_FEBRERO.sql`

1. Abre el **SQL Editor** en Supabase
2. Copia **TODO** el contenido de `FIX_RUTS_ENERO_FEBRERO.sql`
3. Pega y ejecuta en Supabase
4. Verifica que el último SELECT muestre:
   - Enero: ~95 órdenes con RUT `26402839-6`
   - Febrero: ~100 órdenes con RUT `26402839-6`

**¿Qué hace este script?**
- Crea un mapeo entre nombres de técnicos y sus RUTs desde `tecnicos_traza_zc`
- Actualiza todos los registros de Enero y Febrero que tengan RUT vacío o timestamp
- Valida que las correcciones se aplicaron correctamente

**⏱️ Tiempo estimado**: 2-3 minutos

---

### **PASO 2️⃣: Actualizar el AppScript**

**Archivo**: `APPSCRIPT_TRAZA_CORREGIDO.js`

1. Abre tu proyecto en **Google Apps Script** (script.google.com)
2. **BORRA TODO** el código actual
3. Copia **TODO** el contenido de `APPSCRIPT_TRAZA_CORREGIDO.js`
4. Pega en Apps Script
5. Guarda el proyecto
6. Ejecuta la función `pruebaProduccionTRAZA()` para probar

**¿Qué cambió?**

#### **ANTES (líneas 40 y 77 del script viejo):**
```javascript
const rutBucket = (fila["Rut o Bucket"] || "").toString().trim(); // ❌ RUT del cliente
// ...
rut_tecnico: rutBucket, // ❌ Asigna RUT del cliente
```

#### **DESPUÉS (líneas 70-92 del script corregido):**
```javascript
// ✅ EXTRAER RUT Y NOMBRE DEL TÉCNICO CORRECTAMENTE
// Formato: "TRAZ_26402839-6_Alberto Escalona G"
const partes = tecnicoCompleto.split("_");

let rutTecnico = "";
let nombreTecnico = "";

if (partes.length >= 3) {
  // Formato esperado: ["TRAZ", "26402839-6", "Alberto Escalona G"]
  rutTecnico = partes[1]; // ✅ El RUT está en la segunda posición
  nombreTecnico = partes.slice(2).join(" "); // ✅ El nombre puede tener espacios
} else if (partes.length === 2) {
  // Formato alternativo: ["TRAZ", "Alberto Escalona G"]
  nombreTecnico = partes[1];
  rutTecnico = ""; // No hay RUT disponible
} else {
  // Formato no reconocido
  nombreTecnico = tecnicoCompleto;
  rutTecnico = "";
}

// Limpiar el RUT (quitar espacios y caracteres extraños)
rutTecnico = rutTecnico.trim();

// Validar que el RUT tenga formato correcto (ej: 12345678-9)
const rutRegex = /^\d{7,8}-[\dkK]$/;
if (!rutRegex.test(rutTecnico)) {
  Logger.log("⚠️ RUT inválido para " + nombreTecnico + ": '" + rutTecnico + "'");
  rutTecnico = ""; // Dejar vacío si no es válido
}
```

**Mejoras adicionales:**
- ✅ Valida formato del RUT (8 dígitos + guion + dígito verificador)
- ✅ Registra en el log los técnicos sin RUT
- ✅ Muestra estadísticas de RUTs procesados
- ✅ Maneja diferentes formatos del campo "Técnico"

**⏱️ Tiempo estimado**: 5 minutos

---

### **PASO 3️⃣: Probar la app**

1. **Desinstala** la app actual de tu teléfono
2. **Compila** el nuevo APK:
   ```bash
   cd C:\Users\Usuario\trazabox
   flutter clean
   flutter build apk --release
   ```
3. **Instala** el nuevo APK en tu teléfono
4. **Regístrate** con Alberto Escalona (`26402839-6`)
5. **Verifica** que en "Tu Mes" ahora aparezcan:
   - **Card IZQUIERDO (Enero)**: ~106 RGU
   - **Card DERECHO (Febrero)**: ~75 RGU

**⏱️ Tiempo estimado**: 10 minutos (compilación + instalación + prueba)

---

## 📊 **VERIFICACIÓN FINAL**

### **Consulta de verificación en Supabase:**

```sql
-- Ver datos de Alberto Escalona en Enero (debe mostrar ~95 órdenes con RUT correcto)
SELECT 
    rut_tecnico,
    COUNT(*) as ordenes,
    COUNT(*) FILTER (WHERE estado = 'Completado') as completadas,
    ROUND(SUM(rgu_total) FILTER (WHERE estado = 'Completado'), 2) as rgu_total
FROM produccion
WHERE tecnico = 'Alberto Escalona G'
  AND (fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%')
GROUP BY rut_tecnico;
```

**Resultado esperado:**
| rut_tecnico | ordenes | completadas | rgu_total |
|-------------|---------|-------------|-----------|
| 26402839-6  | 95      | 95          | ~106.00   |

---

## 🎯 **¿POR QUÉ PASÓ ESTO?**

El campo `"Rut o Bucket"` en la API de Kepler **NO es el RUT del técnico**:
- A veces es el RUT del cliente
- A veces es un identificador de bucket
- A veces está vacío

El RUT del técnico **siempre** viene en el campo `"Técnico"` con el formato:
```
TRAZ_[RUT]_[NOMBRE]
```

Ejemplos reales:
- `TRAZ_26402839-6_Alberto Escalona G` ✅
- `TRAZ_17926483-8_Hernan Carrasco V` ✅
- `TRAZ_18765432-1_Francisco Chirinos A` ✅

---

## 🚀 **PRÓXIMOS PASOS**

1. ✅ Ejecuta `FIX_RUTS_ENERO_FEBRERO.sql`
2. ✅ Actualiza el AppScript
3. ✅ Prueba la ejecución manual del AppScript
4. ✅ Espera 15 minutos para que el trigger automático se ejecute
5. ✅ Verifica que los nuevos datos se carguen con RUT correcto
6. ✅ Compila y prueba la app

---

## 📝 **NOTAS IMPORTANTES**

1. El SQL solo corrige **Enero y Febrero 2026**
2. Si tienes datos de otros meses con el mismo problema, ejecuta el SQL ajustando las fechas
3. El AppScript corregido funcionará para **todos los datos futuros**
4. Si un técnico NO está en `tecnicos_traza_zc`, su RUT NO se corregirá automáticamente
5. Los técnicos sin RUT se registrarán en el log del AppScript

---

## ✅ **CHECKLIST DE EJECUCIÓN**

- [ ] Ejecutar `FIX_RUTS_ENERO_FEBRERO.sql` en Supabase
- [ ] Verificar que Alberto Escalona tenga ~95 órdenes en Enero con RUT correcto
- [ ] Actualizar el AppScript con el código corregido
- [ ] Ejecutar `pruebaProduccionTRAZA()` en Apps Script
- [ ] Verificar en el log que los RUTs se extraen correctamente
- [ ] Compilar nuevo APK de la app
- [ ] Instalar y probar la app
- [ ] Verificar que "Tu Mes" muestre los datos de Enero

---

**¿Dudas o problemas?** Comparte el log de Apps Script o el resultado de las consultas SQL.

