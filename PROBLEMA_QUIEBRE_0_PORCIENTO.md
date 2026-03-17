# ⚠️ PROBLEMA: QUIEBRE 0% (TODOS CON 100% EFECTIVIDAD)

## 🔍 **DIAGNÓSTICO REALIZADO:**

### **Consulta SQL a Supabase (Enero 2026):**
```sql
Total órdenes: 2,305
Estado "Completado": 2,305 (100%)
Estado "Cancelado": 0 (0%)
Estado "No Realizada": 0 (0%)
Estado "Suspendido": 0 (0%)
```

### **Conclusión:**
❌ **No hay órdenes con estado diferente a "Completado" en la base de datos**

---

## 🎯 **CAUSA RAÍZ IDENTIFICADA:**

El **endpoint de la API de Kepler** está aplicando un filtro:

```javascript
❌ URL_API: "https://kepler.sbip.cl/api/v1/toa/get_sabana_filtrada/metro/TRAZ"
                                                    ↑
                                              "FILTRADA"
```

La palabra `filtrada` indica que la API **solo devuelve órdenes completadas**.

---

## ✅ **SOLUCIONES:**

### **SOLUCIÓN 1: Cambiar el endpoint (Más probable)** ⭐

En el AppScript, cambiar:

```javascript
// ❌ ANTES:
const CONFIG_TRAZA = {
  URL_API: "https://kepler.sbip.cl/api/v1/toa/get_sabana_filtrada/metro/TRAZ",
  // ...
};

// ✅ DESPUÉS:
const CONFIG_TRAZA = {
  URL_API: "https://kepler.sbip.cl/api/v1/toa/get_sabana/metro/TRAZ",
  // ...
};
```

**Resultado esperado:**
- La API devolverá **todas** las órdenes (completadas, canceladas, no realizadas, suspendidas)
- El AppScript **ya está preparado** para manejarlas (normaliza los estados)
- La app **ya está preparada** para calcular efectividad y % quiebre

---

### **SOLUCIÓN 2: Agregar parámetro a la URL**

Si el endpoint `get_sabana` no existe, prueba:

```javascript
URL_API: "https://kepler.sbip.cl/api/v1/toa/get_sabana_filtrada/metro/TRAZ?incluir_todos=true"
// O:
URL_API: "https://kepler.sbip.cl/api/v1/toa/get_sabana_filtrada/metro/TRAZ?estado=todos"
```

---

### **SOLUCIÓN 3: Consultar al equipo de IT**

Pregúntales:

1. **¿Cuál es el endpoint para obtener TODAS las órdenes?**
   - Necesitamos completadas, canceladas, no realizadas, suspendidas

2. **¿Qué parámetros acepta la API?**
   - ¿Hay un filtro de estado?
   - ¿Cómo incluir todos los estados?

3. **¿Cuál es la diferencia entre estos endpoints?**
   - `/get_sabana/metro/TRAZ`
   - `/get_sabana_filtrada/metro/TRAZ`

---

## 📊 **VERIFICACIÓN POST-CAMBIO:**

Después de cambiar el endpoint, ejecuta estas queries para verificar:

### **1. Ver distribución de estados:**
```sql
SELECT 
    estado,
    COUNT(*) AS cantidad,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS porcentaje
FROM produccion
WHERE fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%'
GROUP BY estado
ORDER BY cantidad DESC;
```

**Resultado esperado:**
```
estado         | cantidad | porcentaje
---------------|----------|------------
Completado     | 2100     | 85.50%
Cancelado      | 150      | 6.11%
No Realizada   | 100      | 4.07%
Suspendido     | 55       | 2.24%
```

---

### **2. Ver técnicos con más quiebres:**
```sql
SELECT 
    rut_tecnico,
    tecnico,
    COUNT(*) FILTER (WHERE estado = 'Completado') AS completadas,
    COUNT(*) FILTER (WHERE estado = 'Cancelado') AS canceladas,
    COUNT(*) FILTER (WHERE estado = 'No Realizada') AS no_realizadas,
    COUNT(*) AS total,
    ROUND(
        (COUNT(*) FILTER (WHERE estado != 'Completado') * 100.0) / COUNT(*), 
        2
    ) AS porcentaje_quiebre
FROM produccion
WHERE fecha_trabajo LIKE '%/01/26%' OR fecha_trabajo LIKE '%/01/2026%'
GROUP BY rut_tecnico, tecnico
HAVING COUNT(*) > 10
ORDER BY porcentaje_quiebre DESC
LIMIT 20;
```

**Resultado esperado:**
```
rut_tecnico  | tecnico       | completadas | canceladas | no_realizadas | total | % quiebre
-------------|---------------|-------------|------------|---------------|-------|----------
11111111-1   | Juan Pérez    | 80          | 10         | 5             | 95    | 15.79%
22222222-2   | María López   | 85          | 8          | 2             | 95    | 10.53%
```

---

### **3. Ver efectividad en la app:**

Después de que el AppScript cargue los datos nuevos:

1. **Abre la app** → **Producción**
2. **Verifica** que ahora muestre:
   - ✅ Efectividad < 100% (ej: 85-95%)
   - ✅ % Quiebre > 0% (ej: 5-15%)
   - ✅ X canceladas
   - ✅ Y no realizadas

---

## 🔧 **CÓDIGO DE LA APP - YA ESTÁ LISTO**

El código de `produccion_service.dart` **ya maneja correctamente** los estados:

```dart
if (estado == 'Completado') {
  completadas++;
} else if (estado == 'Cancelado') {
  canceladas++;
} else if (estado == 'No Realizada') {
  noRealizadas++;
}

final totalAsignadas = completadas + canceladas + noRealizadas;
final efectividad = totalAsignadas > 0
    ? (completadas / totalAsignadas) * 100
    : 0.0;
final porcentajeQuiebre = totalAsignadas > 0
    ? ((canceladas + noRealizadas) / totalAsignadas) * 100
    : 0.0;
```

**No requiere cambios en la app** ✅

---

## 📋 **CHECKLIST DE IMPLEMENTACIÓN:**

### **Fase 1: Cambiar el endpoint**
- [ ] Abrir Google Apps Script
- [ ] Cambiar la URL de `get_sabana_filtrada` a `get_sabana`
- [ ] Guardar cambios
- [ ] Ejecutar `extraerProduccionTRAZA()`

### **Fase 2: Verificar logs del AppScript**
- [ ] Ver el log: "📊 Por estado: {...}"
- [ ] Confirmar que ahora aparecen:
  - ✅ "Completado": X
  - ✅ "Cancelado": Y
  - ✅ "No Realizada": Z

### **Fase 3: Verificar en Supabase**
- [ ] Ejecutar query de estados
- [ ] Confirmar que hay más de 1 estado

### **Fase 4: Verificar en la app**
- [ ] Abrir app
- [ ] Ir a Producción
- [ ] Verificar efectividad < 100%
- [ ] Verificar % quiebre > 0%

---

## 🚀 **PRÓXIMO PASO INMEDIATO:**

**Cambia la URL en el AppScript y ejecuta:**

```javascript
// En Google Apps Script, línea 7:
URL_API: "https://kepler.sbip.cl/api/v1/toa/get_sabana/metro/TRAZ"
```

Luego ejecuta `extraerProduccionTRAZA()` y revisa el log.

**Si aparece un error 404**, contacta al equipo de IT para que te den el endpoint correcto.

