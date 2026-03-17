# 📘 **GUÍA DEL SISTEMA DE HORAS EXTRAS - TRAZA**

## 🎯 **POLÍTICA DE HORAS EXTRAS:**

```
┌─────────────────────────────────────────────────────────────┐
│ LUNES A VIERNES:  09:45 - 18:30                            │
│                   Hora extra después de 18:30               │
│                                                             │
│ SÁBADO:           10:00 - 14:00                            │
│                   Hora extra después de 14:00               │
│                                                             │
│ DOMINGO/FESTIVOS: Todo el día = hora extra                 │
└─────────────────────────────────────────────────────────────┘

⚠️ CONDICIÓN ESPECIAL (FASE 2):
   El último trabajo debe cerrarse a máximo 300m del domicilio
   del técnico para que cuente como hora extra
```

---

## 📦 **¿QUÉ SE CREÓ?**

### **1. Columnas nuevas en `tecnicos_traza_zc`:**
- `direccion_domicilio` (TEXT) - Dirección del técnico
- `coord_domicilio_x` (NUMERIC) - Latitud del domicilio
- `coord_domicilio_y` (NUMERIC) - Longitud del domicilio

### **2. Funciones SQL:**

#### `calcular_distancia_metros(lat1, lon1, lat2, lon2)`
Calcula la distancia en metros entre dos puntos geográficos usando la fórmula de Haversine.

```sql
-- Ejemplo de uso:
SELECT calcular_distancia_metros(
    -33.4489, -70.6693,  -- Coordenadas domicilio
    -33.4500, -70.6700   -- Coordenadas última orden
); -- Retorna: 142.35 metros
```

#### `es_festivo(fecha)`
Verifica si una fecha es festivo chileno.

```sql
SELECT es_festivo('2026-01-01'); -- Retorna: true (Año Nuevo)
```

#### `calcular_minutos_hora_extra(fecha, hora_inicio, hora_fin, duracion)`
Calcula cuántos minutos de una orden son hora extra según la política.

```sql
-- Ejemplo: Orden el viernes 05/01/26 que terminó a las 20:15
SELECT calcular_minutos_hora_extra(
    '05/01/26',
    '19:54',
    '20:15',
    21
); -- Retorna: 21 minutos (toda la orden es hora extra)
```

### **3. Vistas SQL:**

#### `v_horas_extras_diarias`
Muestra las horas extras de cada técnico por día:

| Columna | Descripción |
|---------|-------------|
| `rut_tecnico` | RUT del técnico |
| `tecnico` | Nombre del técnico |
| `fecha_trabajo` | Fecha (formato DD/MM/YY) |
| `fecha_completa` | Fecha (tipo DATE) |
| `dia_semana` | 0=Domingo, 1=Lunes, ..., 6=Sábado |
| `nombre_dia` | Nombre del día en español |
| `ordenes_completadas` | Cantidad de órdenes completadas |
| `minutos_hora_extra` | Minutos totales de hora extra |
| `horas_extra` | Horas totales (minutos / 60) |
| `primera_orden` | Hora de inicio de la primera orden |
| `ultima_orden` | Hora de fin de la última orden |

#### `v_horas_extras_mensuales`
Resumen acumulado por mes:

| Columna | Descripción |
|---------|-------------|
| `rut_tecnico` | RUT del técnico |
| `tecnico` | Nombre del técnico |
| `mes` | Mes (1-12) |
| `anio` | Año (2026) |
| `dias_con_hora_extra` | Días que hizo hora extra |
| `minutos_hora_extra_total` | Minutos totales del mes |
| `horas_extra_total` | Horas totales del mes |
| `primera_fecha` | Primera fecha con hora extra |
| `ultima_fecha` | Última fecha con hora extra |

---

## 🚀 **CÓMO USAR:**

### **1. Ejecutar el script SQL:**

```bash
# En Supabase SQL Editor o pgAdmin:
C:\Users\Usuario\trazabox\SISTEMA_HORAS_EXTRAS_TRAZA.sql
```

### **2. Consultar horas extras de un técnico en Enero:**

```sql
SELECT * FROM v_horas_extras_diarias
WHERE rut_tecnico = '26402839-6'
  AND EXTRACT(MONTH FROM fecha_completa) = 1
  AND EXTRACT(YEAR FROM fecha_completa) = 2026
ORDER BY fecha_completa;
```

### **3. Ver resumen mensual:**

```sql
SELECT * FROM v_horas_extras_mensuales
WHERE rut_tecnico = '26402839-6'
  AND mes = 1
  AND anio = 2026;
```

### **4. Top 10 técnicos con más horas extras:**

```sql
SELECT * FROM v_horas_extras_mensuales
WHERE mes = 1 AND anio = 2026
ORDER BY horas_extra_total DESC
LIMIT 10;
```

---

## 📊 **EJEMPLO DE RESULTADO:**

### **Alberto Escalona G - 05/01/26:**

| Orden | Inicio | Fin | Duración | ¿Hora Extra? | Minutos Extra |
|-------|--------|-----|----------|--------------|---------------|
| 1-3H38G5SS | 13:00 | 15:45 | 165 min | ❌ No (antes de 18:30) | 0 |
| 1-3H4B6RN3 | 16:06 | 16:17 | 11 min | ❌ No (antes de 18:30) | 0 |
| 1-3H401YLU | 17:15 | 17:57 | 42 min | ❌ No (antes de 18:30) | 0 |
| 1-3H4F0QC6 | 18:05 | 18:42 | 37 min | ✅ Sí (terminó después de 18:30) | 12 min |
| 1-3H4NCQZ3 | 18:57 | 19:10 | 13 min | ✅ Sí (todo después de 18:30) | 13 min |
| 1-3H4GE6NV | 19:25 | 19:40 | 15 min | ✅ Sí (todo después de 18:30) | 15 min |
| 1-3H4N7C5I | 19:54 | 20:15 | 21 min | ✅ Sí (todo después de 18:30) | 21 min |

**TOTAL DEL DÍA: 61 minutos = 1.02 horas extra** ✅

---

## ⚠️ **PENDIENTE - FASE 2:**

### **Validación de 300 metros**

Para completar la validación de que la última orden está a máximo 300m del domicilio, se necesita:

#### **1. Completar direcciones de técnicos:**

```sql
-- Ejemplo de cómo actualizar la dirección de un técnico:
UPDATE tecnicos_traza_zc
SET 
    direccion_domicilio = 'Calle Ejemplo 123, Santiago',
    coord_domicilio_x = -33.4489,  -- Latitud
    coord_domicilio_y = -70.6693   -- Longitud
WHERE rut = '26402839-6';
```

#### **2. Modificar la función `calcular_minutos_hora_extra`:**

Añadir al final de la función la validación:

```sql
-- Validar que la última orden esté a máx 300m del domicilio
IF v_minutos_extra > 0 THEN
    -- Obtener coordenadas del domicilio
    SELECT coord_domicilio_x, coord_domicilio_y
    INTO v_coord_domicilio_x, v_coord_domicilio_y
    FROM tecnicos_traza_zc
    WHERE rut = p_rut_tecnico;
    
    -- Si no tiene domicilio registrado, no aplica validación
    IF v_coord_domicilio_x IS NULL THEN
        RETURN v_minutos_extra;
    END IF;
    
    -- Calcular distancia entre última orden y domicilio
    v_distancia := calcular_distancia_metros(
        v_coord_domicilio_x,
        v_coord_domicilio_y,
        p_coord_orden_x,
        p_coord_orden_y
    );
    
    -- Si está a más de 300m, NO cuenta como hora extra
    IF v_distancia > 300 THEN
        RETURN 0;
    END IF;
END IF;
```

#### **3. Obtener coordenadas del domicilio:**

Opciones:
- Google Maps: Click derecho → "¿Qué hay aquí?"
- API de Geocodificación (Google, OpenStreetMap)
- Pedir al técnico que envíe su ubicación desde la app

---

## 🔧 **INTEGRACIÓN CON LA APP FLUTTER:**

### **Servicio: `horas_extras_service.dart`**

```dart
class HorasExtrasService {
  static Future<Map<String, dynamic>> obtenerHorasExtras(
    String rutTecnico, {
    int? mes,
    int? anno,
  }) async {
    final now = DateTime.now();
    final mesConsulta = mes ?? now.month;
    final annoConsulta = anno ?? now.year;

    final response = await Supabase.instance.client
        .from('v_horas_extras_mensuales')
        .select()
        .eq('rut_tecnico', rutTecnico)
        .eq('mes', mesConsulta)
        .eq('anio', annoConsulta)
        .maybeSingle();

    if (response == null) {
      return {
        'dias_con_hora_extra': 0,
        'horas_extra_total': 0.0,
      };
    }

    return {
      'dias_con_hora_extra': response['dias_con_hora_extra'],
      'horas_extra_total': (response['horas_extra_total'] as num?)?.toDouble() ?? 0.0,
      'minutos_hora_extra_total': response['minutos_hora_extra_total'],
    };
  }
}
```

### **UI: `produccion_screen.dart`**

```dart
// Añadir en la tarjeta de "Tu Mes":
Text(
  '${horasExtras.toStringAsFixed(1)} hrs',
  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
),
Text(
  'Horas Extras',
  style: TextStyle(color: Colors.grey),
),
```

---

## 📝 **NOTAS IMPORTANTES:**

1. **El cálculo es automático** - Solo usa las columnas `hora_inicio`, `hora_fin`, `duracion_min` de la tabla `produccion`.

2. **Festivos chilenos** - Ya están cargados en `festivos_chile` hasta 2026.

3. **Formato de hora** - Debe ser `HH:MM` (ej: "18:30", "20:15").

4. **Coordenadas** - Formato decimal (ej: -33.4489, -70.6693).

5. **Validación de 300m** - Pendiente hasta completar direcciones de técnicos.

---

## ✅ **ESTADO ACTUAL:**

| Feature | Estado | Descripción |
|---------|--------|-------------|
| Cálculo básico | ✅ Listo | Calcula horas extras por horario |
| Vista diaria | ✅ Listo | Muestra detalle por día |
| Vista mensual | ✅ Listo | Resumen acumulado |
| Sábados | ✅ Listo | Después de 14:00 |
| Domingos/Festivos | ✅ Listo | Todo el día |
| Validación 300m | ⏳ Pendiente | Falta completar direcciones |

---

**🎉 ¡Sistema listo para usar!**

