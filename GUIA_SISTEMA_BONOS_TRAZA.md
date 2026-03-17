# 📊 Guía del Sistema de Bonos TRAZA

## 🎯 Diferencias clave con Creaciones Tecnológicas

| Concepto | Creaciones | TRAZA |
|----------|-----------|-------|
| **Modelo** | RGU promedio diario | RGU total mensual |
| **Escalas** | Producción + Calidad (separadas) | Matriz única (Producción × Calidad) |
| **Tecnologías** | Una sola | FTTH, NTT, HFC |
| **Cálculo calidad** | % reiteración | % calidad (100 - % reiteración) |
| **Rango bonos** | $240k - $450k | $800 - $9,700 |

---

## 📋 Sistema de Puntos RGU (FTTH)

```
Tipo de Orden          Puntos RGU
──────────────────────────────────
1 Play                    1.00
2 Play                    2.00
3 Play                    3.00
Modificación              0.75
Extensor Adicional        0.75
Decodificador Adicional   0.50
```

**Ejemplo:**
- Técnico hace 10 órdenes:
  - 3 × 3 Play = 9.00
  - 5 × 2 Play = 10.00
  - 2 × Modificación = 1.50
- **Total: 20.50 RGU**

---

## 🔢 Cálculo de Bono FTTH

### Paso 1: Calcular RGU Total
```sql
RGU Total = Σ (puntos_rgu de todas las órdenes completadas del mes)
```

### Paso 2: Calcular % Calidad
```sql
% Calidad = 100 - (órdenes_reiteradas / órdenes_completadas × 100)
```

**Ejemplo:**
- 50 órdenes completadas
- 4 órdenes reiteradas
- % Reiteración = 4/50 × 100 = 8%
- **% Calidad = 100 - 8 = 92%**

### Paso 3: Buscar en Matriz FTTH

```
        0%     8%     9%     10%    11%    12%    13%    14%    15%    16%    17%
     ┌─────────────────────────────────────────────────────────────────────────┐
0-52 │ $3,300 $3,250 $3,150 $2,950 $2,700 $2,200  $800   $800   $800   $800   $800
53-57│ $4,300 $4,250 $4,150 $3,950 $3,700 $3,200 $2,700  $800   $800   $800   $800
58-61│ $5,300 $5,250 $5,150 $4,950 $4,700 $4,200 $3,700 $3,200  $800   $800   $800
...
```

**Con el ejemplo:**
- RGU Total: 20.50
- % Calidad: 92% (columna 8%)
- Rango: 0-52 (fila 1)
- **Bono: $3,250**

---

## 🔢 Cálculo de Bono NTT (Neutra)

### Paso 1: Contar Actividades
```sql
Total Actividades = COUNT(órdenes completadas del mes)
```

### Paso 2: Calcular % Calidad
```sql
% Calidad = 100 - (órdenes_reiteradas / órdenes_completadas × 100)
```

### Paso 3: Buscar en Matriz NTT

```
          0%     9%     11%    13%    15%    17%    19%    21%    23%
       ┌─────────────────────────────────────────────────────────────┐
77-82  │  $950   $950   $800   $650   $500   $150   $100    $50    -
87-92  │ $1,450 $1,450 $1,300 $1,150 $1,000  $450   $300   $150    -
...
147-152│ $5,200 $5,200 $5,050 $4,900 $4,750 $3,250 $2,250 $1,250 $1,050
```

---

## 🗄️ Estructura de Tablas

### **1. tipos_orden**
Catálogo de tipos de orden con puntos RGU
```sql
id | codigo          | nombre                   | puntos_rgu | tecnologia
1  | 1_PLAY          | 1 Play                   | 1.00       | FTTH
2  | 2_PLAY          | 2 Play                   | 2.00       | FTTH
3  | 3_PLAY          | 3 Play                   | 3.00       | FTTH
4  | MODIFICACION    | Modificación             | 0.75       | FTTH
5  | EXTENSOR        | Extensor Adicional       | 0.75       | FTTH
6  | DECODIFICADOR   | Decodificador Adicional  | 0.50       | FTTH
```

### **2. escala_ftth**
Matriz de bonos RGU × Calidad (27 filas × 12 columnas)

### **3. escala_ntt**
Matriz de bonos Actividades × Calidad (29 filas × 9 columnas)

### **4. produccion_traza**
Órdenes de trabajo con puntos RGU
```sql
id | rut_tecnico | tecnico    | fecha_trabajo | orden_trabajo | tipo_orden | tecnologia | puntos_rgu | estado
1  | 12345678-9  | Juan Pérez | 1/12/2025     | OT-001       | 2_PLAY     | FTTH       | 2.00       | Completado
```

### **5. calidad_traza**
Reiteraciones para cálculo de % calidad
```sql
id | rut_tecnico | orden_original | fecha_original | orden_reiterada | fecha_reiterada | tecnologia
1  | 12345678-9  | OT-001        | 1/12/2025      | OT-002         | 5/12/2025       | FTTH
```

### **6. pagos_traza**
Bonos calculados por técnico/período/tecnología
```sql
id | rut_tecnico | periodo | tecnologia | rgu_total | ordenes_completadas | porcentaje_calidad | monto_bono
1  | 12345678-9  | 2025-12 | FTTH       | 65.5      | 50                  | 92.00              | 4250
```

---

## 🔧 Funciones SQL Principales

### **1. obtener_puntos_rgu(tipo_orden)**
Retorna puntos RGU según tipo de orden
```sql
SELECT obtener_puntos_rgu('2_PLAY'); -- Retorna: 2.00
```

### **2. obtener_bono_ftth(rgu_total, porcentaje_calidad)**
Busca bono en matriz FTTH
```sql
SELECT obtener_bono_ftth(60.0, 92.0); -- Retorna: 4250
```

### **3. obtener_bono_ntt(actividades_total, porcentaje_calidad)**
Busca bono en matriz NTT
```sql
SELECT obtener_bono_ntt(100, 90.0); -- Retorna: 4000
```

---

## 📝 Flujo de Trabajo

### **1. Carga de Datos (AppScript → Supabase)**
```
AppScript ejecuta diariamente
      ↓
Obtiene órdenes del día
      ↓
Inserta en produccion_traza
      ↓
Actualiza puntos_rgu según tipo_orden
```

### **2. Cálculo Mensual de Bonos**
```sql
-- Al final del mes:
1. Calcular RGU total por técnico
2. Contar órdenes completadas
3. Contar órdenes reiteradas
4. Calcular % calidad
5. Buscar bono en matriz
6. Guardar en pagos_traza
```

### **3. Visualización en App**
```
App TrazaBox
      ↓
Consulta v_pagos_traza
      ↓
Muestra dashboard con:
  - RGU total
  - % Calidad
  - Monto bono
  - Ranking
```

---

## 🚀 Instrucciones de Instalación

### **Paso 1: Ejecutar en Supabase**
1. Ir a Supabase → SQL Editor
2. Ejecutar `SISTEMA_BONOS_TRAZA_COMPLETO.sql`
3. Verificar que se crearon todas las tablas

### **Paso 2: Verificar Instalación**
```sql
-- Ver tablas creadas
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name LIKE '%traza%';

-- Verificar escalas
SELECT COUNT(*) FROM escala_ftth; -- Debe retornar: 27
SELECT COUNT(*) FROM escala_ntt;  -- Debe retornar: 29

-- Probar funciones
SELECT obtener_bono_ftth(60.0, 92.0); -- Debe retornar: 4250
SELECT obtener_bono_ntt(100, 90.0);   -- Debe retornar: 4000
```

---

## 📊 Próximos Pasos

### **Fase 1: Completar Base de Datos** ✅
- ✅ Tablas creadas
- ✅ Escalas pobladas
- ✅ Funciones implementadas
- ⏳ Crear función de cálculo automático mensual
- ⏳ Crear trigger para actualizar puntos RGU

### **Fase 2: Integración con AppScript**
- ⏳ Script de carga diaria de órdenes
- ⏳ Script de sincronización de reiteraciones
- ⏳ Validación de datos

### **Fase 3: Adaptación de App**
- ⏳ Actualizar modelos Dart
- ⏳ Modificar pantallas (producción, calidad)
- ⏳ Adaptar cálculos y KPIs

### **Fase 4: Testing**
- ⏳ Probar cálculos con datos reales
- ⏳ Validar bonos vs. escalas
- ⏳ Verificar App completa

---

## ❓ Preguntas Frecuentes

### **1. ¿Qué pasa si un técnico tiene FTTH y NTT en el mismo mes?**
Se calculan 2 bonos separados, uno por cada tecnología.

### **2. ¿Cómo se actualiza el tipo de orden si viene mal desde AppScript?**
```sql
UPDATE produccion_traza 
SET tipo_orden = '3_PLAY', 
    puntos_rgu = 3.0
WHERE orden_trabajo = 'OT-123';
```

### **3. ¿Cómo recalcular bonos de un mes?**
```sql
-- Eliminar bonos existentes
DELETE FROM pagos_traza WHERE periodo = '2025-12';

-- Ejecutar cálculo de ejemplo en EJEMPLO_USO_BONOS_TRAZA.sql
```

### **4. ¿Cómo agregar nuevos tipos de orden?**
```sql
INSERT INTO tipos_orden (codigo, nombre, puntos_rgu, tecnologia) 
VALUES ('4_PLAY', '4 Play', 4.00, 'FTTH');
```

---

**Fecha:** 2026-02-03  
**Versión:** 1.0  
**Autor:** Sistema TrazaBox

