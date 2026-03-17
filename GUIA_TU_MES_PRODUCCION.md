# 📊 GUÍA: "TU MES" - MOSTRAR PRODUCCIÓN EN TRAZABOX

## 🎯 Objetivo
Mostrar al técnico su producción del mes actual: órdenes completadas, RGU acumulado, días trabajados, etc.

---

## ✅ Estado Actual

### Código ya adaptado:
- ✅ `ProduccionService` → Ahora consulta `produccion_traza` (antes `produccion_crea`)
- ✅ `TecnicoService` → Valida RUT contra `produccion_traza`
- ✅ Pantalla `tu_mes_screen.dart` → Lista para mostrar datos

### Tablas en Supabase TRAZA:
- ✅ `produccion_traza` → Contiene las órdenes con RGU
- ✅ `calidad_traza` → Para reiteraciones (cuando TI las cree)
- ✅ `tipos_orden` → Catálogo de tipos de orden con puntos RGU

---

## 📋 Datos que muestra "Tu Mes"

La pantalla muestra varios cards con información:

### 1️⃣ **Card de Producción**
- **Total RGU del mes**
- **Promedio RGU/día**
- **Órdenes completadas**
- **Días trabajados**

```dart
// Consulta desde produccion_traza
Future<Map<String, dynamic>> obtenerResumenMesRGU(
  String rutTecnico, {
  int? mes,
  int? anno,
})
```

### 2️⃣ **Card de Calidad** (Pendiente - esperando tablas de TI)
- Porcentaje de reiteración
- Órdenes reiteradas
- Días promedio entre instalación y reiteración

### 3️⃣ **Card de Reversa** (Opcional)
- Equipos pendientes de entrega
- Equipos entregados en bodega

---

## 🔧 Cómo funciona actualmente

### Flujo de datos:

1. **Usuario abre la app** → Registrado con su RUT
2. **Navega a "Tu Mes"** → `tu_mes_screen.dart`
3. **La pantalla consulta**:
   ```dart
   ProduccionService().obtenerResumenMesRGU(rutTecnico, mes: mesActual, anno: annoActual)
   ```
4. **El servicio consulta Supabase**:
   ```sql
   SELECT * FROM produccion_traza 
   WHERE rut_tecnico = '12345678-9'
   AND fecha_trabajo LIKE '%/2/%/2026'  -- Febrero 2026
   AND estado = 'Completado'
   ```
5. **Calcula totales**:
   - Suma RGU de todas las órdenes
   - Cuenta días únicos con producción
   - Calcula promedio RGU/día

---

## 🧪 Cómo probar

### Paso 1: Agregar más órdenes al técnico de prueba

Ejecuta en Supabase TRAZA:

```sql
-- Agregar órdenes de febrero 2026 para el técnico
INSERT INTO produccion_traza (
    rut_tecnico, 
    tecnico, 
    fecha_trabajo, 
    orden_trabajo, 
    tipo_orden, 
    tecnologia, 
    puntos_rgu, 
    estado
)
VALUES
    -- Día 1 de febrero
    ('12345678-9', 'Juan Pérez González', '01/02/2026', 'OT-2026-010', '3_PLAY', 'FTTH', 3.00, 'Completado'),
    ('12345678-9', 'Juan Pérez González', '01/02/2026', 'OT-2026-011', '2_PLAY', 'FTTH', 2.00, 'Completado'),
    
    -- Día 3 de febrero
    ('12345678-9', 'Juan Pérez González', '03/02/2026', 'OT-2026-012', '3_PLAY', 'FTTH', 3.00, 'Completado'),
    ('12345678-9', 'Juan Pérez González', '03/02/2026', 'OT-2026-013', 'MODIFICACION', 'FTTH', 0.75, 'Completado'),
    
    -- Día 4 de febrero
    ('12345678-9', 'Juan Pérez González', '04/02/2026', 'OT-2026-014', '3_PLAY', 'FTTH', 3.00, 'Completado'),
    ('12345678-9', 'Juan Pérez González', '04/02/2026', 'OT-2026-015', '1_PLAY', 'FTTH', 1.00, 'Completado');

-- Verificar
SELECT 
    rut_tecnico,
    tecnico,
    COUNT(*) as total_ordenes,
    SUM(puntos_rgu) as total_rgu
FROM produccion_traza
WHERE rut_tecnico = '12345678-9'
  AND fecha_trabajo LIKE '%/02/2026'
  AND estado = 'Completado'
GROUP BY rut_tecnico, tecnico;
```

### Paso 2: Abrir "Tu Mes" en la app

1. Abre TrazaBox
2. En el menú principal (HomeScreen), busca el botón/card de **"Tu Mes"**
3. Deberías ver:
   - **Total RGU**: ~12.75 (suma de todas las órdenes)
   - **Promedio RGU/día**: ~4.25 (12.75 / 3 días)
   - **Órdenes completadas**: 6
   - **Días trabajados**: 3

---

## 📱 Acceder a "Tu Mes" desde la app

Busca en el código dónde está el botón/navegación a "Tu Mes":

```dart
// En home_screen.dart o similar
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const TuMesScreen()),
);
```

---

## 🔍 Troubleshooting

### Problema: No muestra datos

**Solución:**
1. Verifica que el RUT guardado en `SharedPreferences` coincide con las órdenes
   ```dart
   final prefs = await SharedPreferences.getInstance();
   final rut = prefs.getString('rut_tecnico');
   print('RUT guardado: $rut');
   ```

2. Verifica que las fechas en `produccion_traza` tienen el formato correcto: `DD/MM/YYYY`

3. Revisa logs en la consola:
   ```
   flutter run --release
   ```
   Busca mensajes como:
   ```
   📊 [Produccion] Resumen final mes: 2/2026
      - Órdenes completadas: X
      - Total RGU: X.XX
   ```

### Problema: Error de tabla no existe

**Solución:**
1. Verifica que `produccion_traza` existe en Supabase TRAZA:
   ```sql
   SELECT * FROM produccion_traza LIMIT 1;
   ```

2. Si no existe, ejecuta `SISTEMA_BONOS_TRAZA_COMPLETO.sql`

---

## 🚀 Próximos pasos

1. ✅ **Producción funcionando** (actual)
2. ⏳ **Calidad** → Esperar tablas de TI
3. ⏳ **Marcas de asistencia** → Integrar cuando tengas datos de GeoVictoria/similar
4. ⏳ **Reversa** → Si aplica para TRAZA

---

¿Necesitas ayuda para:
- Agregar más datos de prueba?
- Encontrar el botón de "Tu Mes" en la app?
- Debuggear por qué no muestra datos?

