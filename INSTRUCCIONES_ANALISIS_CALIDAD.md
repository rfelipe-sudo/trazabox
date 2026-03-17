# 🔍 **INSTRUCCIONES: ANÁLISIS DE DATOS DE CALIDAD**

## 🎯 **OBJETIVO:**

Ejecutar un script de prueba para ver **qué columnas trae el API de Kepler** y entender cómo calcular las reiteraciones con el desfase de 1 mes.

---

## 📋 **PASO A PASO:**

### **1️⃣ ABRIR GOOGLE APPS SCRIPT**

```
https://script.google.com
```

### **2️⃣ CREAR NUEVO PROYECTO**

- Clic en **Nuevo proyecto**
- Nombre: "Análisis Calidad TRAZA"

### **3️⃣ COPIAR EL CÓDIGO**

- Abrir archivo: `APPSCRIPT_CALIDAD_PRUEBA.js`
- Copiar **TODO** el contenido
- Pegar en Apps Script
- Guardar (💾)

### **4️⃣ EJECUTAR LA FUNCIÓN**

- En el dropdown de funciones, seleccionar: `analizarDatosCalidad`
- Hacer clic en **Ejecutar** (▶️)
- Si pide autorización (primera vez):
  1. Clic en "Revisar permisos"
  2. Seleccionar tu cuenta
  3. Clic en "Ir a Análisis Calidad TRAZA (no seguro)"
  4. Clic en "Permitir"
- Esperar a que termine (~1-2 min)

### **5️⃣ VER EL LOG**

- Hacer clic en el icono de **Ejecuciones** (📋)
- O presionar `Ctrl + Enter` para abrir el log
- Copiar **TODO** el contenido del log

---

## 📊 **QUÉ VA A MOSTRAR EL SCRIPT:**

El script analizará los datos y mostrará:

### **1. Columnas disponibles:**
```
📋 COLUMNAS DISPONIBLES:
─────────────────────────────────────────────────
1. access_id (string): 1-337UL6GA
2. orden_de_trabajo (string): 1-3GZVYJJ6
3. fecha (string): 30/12/25
4. es_reiterado (string): NO
5. dias_diferencia (number): null
6. reiterada_por_ot (string): null
7. reiterada_por_fecha (string): null
... (todas las demás columnas)
```

### **2. Ejemplos de reiteraciones:**
```
🔸 REITERACIÓN 1:
   Orden actual: 1-3HDTTRB1
   Fecha actual: 15/01/26
   Técnico actual: Pedro Aldana
   ────────────────────────────────────────
   ⚠️ DATOS DE LA ORDEN ORIGINAL:
   Orden original: 1-3H5USGVU
   Fecha original: 08/01/26
   Técnico original: Pedro Aldana
   Días de diferencia: 7
```

### **3. Distribución de días:**
```
📊 DISTRIBUCIÓN DE DÍAS DE DIFERENCIA:
Min: 1 días
Max: 45 días
Promedio: 12.34 días
✅ Dentro de 30 días: 850 (95.51%)
❌ Fuera de 30 días: 40 (4.49%)
```

### **4. Análisis del desfase:**
```
📅 ANÁLISIS DE FECHAS (DESFASE DE MES):
1. Orden: 1-3HDTTRB1
   Original: 08/01/26 (mes 1)
   Reiteración: 15/01/26 (mes 1)
   Desfase: 0 mes(es), 7 días
   ¿Válido? ✅ SÍ

2. Orden: 1-3HCDD7HL
   Original: 25/01/26 (mes 1)
   Reiteración: 18/02/26 (mes 2)
   Desfase: 1 mes(es), 24 días
   ¿Válido? ✅ SÍ

3. Orden: 1-3HG8K2MN
   Original: 05/01/26 (mes 1)
   Reiteración: 10/03/26 (mes 3)
   Desfase: 2 mes(es), 64 días
   ¿Válido? ❌ NO (más de 1 mes)
```

---

## 💬 **QUÉ NECESITO QUE ME COMPARTAS:**

Después de ejecutar el script, copia el log completo y compártelo conmigo para que pueda:

1. ✅ Ver todas las columnas disponibles
2. ✅ Entender cómo vienen las fechas
3. ✅ Ver ejemplos reales de reiteraciones
4. ✅ Confirmar cómo funciona el desfase de mes
5. ✅ Ajustar la lógica SQL según los datos reales

---

## 📝 **EJEMPLO DE LO QUE DEBO VER:**

```
═════════════════════════════════════════════════
🔍 ANÁLISIS: Datos de Calidad TRAZA
═════════════════════════════════════════════════

📡 Consultando API de Kepler...
✅ Registros obtenidos: 31289
📅 Fecha de ejecución: 2026-02-16 16:21:47

🔍 ANÁLISIS DE ESTRUCTURA:
═════════════════════════════════════════════════

📋 COLUMNAS DISPONIBLES:
─────────────────────────────────────────────────
1. access_id (string): 1-337UL6GA
2. orden_de_trabajo (string): 1-3GZVYJJ6
3. rut_o_bucket (string): 26494163-6
4. tecnico (string): FS_NFTT_TRAZ_Pedro Aldana D
5. fecha (string): 30/12/25
6. es_reiterado (string): NO
7. dias_diferencia (object): null
8. reiterada_por_ot (object): null
... (etc)

🔍 BUSCANDO REITERACIONES:
═════════════════════════════════════════════════
✅ Reiteraciones encontradas: 1234 de 31289 (3.94%)

📊 EJEMPLOS DE REITERACIONES (primeras 5):
... (ejemplos detallados)

📊 DISTRIBUCIÓN DE DÍAS DE DIFERENCIA:
... (estadísticas)

📅 ANÁLISIS DE FECHAS (DESFASE DE MES):
... (análisis del desfase)
```

---

## ⚠️ **IMPORTANTE:**

Este script **NO inserta datos en Supabase**, solo los descarga y analiza. Es 100% seguro ejecutarlo.

---

## 🎯 **SIGUIENTE PASO:**

Una vez que me compartas el log completo, voy a:

1. ✅ Entender cómo calcular el período de calidad con desfase
2. ✅ Ajustar la tabla SQL si es necesario
3. ✅ Crear la vista SQL con la lógica correcta
4. ✅ Actualizar el AppScript de carga final

---

**¿Listo para ejecutar?** 🚀

Ejecuta el script y pégame el log completo del resultado.

