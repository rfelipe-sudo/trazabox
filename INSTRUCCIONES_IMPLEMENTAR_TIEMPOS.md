# 📋 **INSTRUCCIONES: IMPLEMENTAR SISTEMA DE TIEMPOS (INICIO TARDÍO + HORAS EXTRAS)**

## 🎯 **OBJETIVO:**

Hacer que la app muestre correctamente:
- ⏰ **Inicio tardío**: Minutos que inició tarde según su turno
- ⏳ **Horas extras**: Minutos que trabajó después del horario según su turno

## 🕐 **TURNOS SOPORTADOS:**

| Turno | L-V Horario | Sábado | Inicio Tardío (L-V) | Hora Extra (L-V) |
|-------|-------------|--------|---------------------|------------------|
| **5x2** | 09:15 - 19:00 | 10:00 - 14:00 | Después de 09:15 | Después de 19:00 |
| **6x1** | 09:45 - 18:30 | 10:00 - 14:00 | Después de 09:45 | Después de 18:30 |

**Nota:** El turno de cada técnico se lee automáticamente de la columna `tipo_turno` en `tecnicos_traza_zc`.

📖 **Ver más detalles:** `TABLA_COMPARACION_TURNOS.md`

---

## 📦 **ARCHIVOS CREADOS:**

1. ✅ `SISTEMA_TIEMPOS_COMPLETO_TRAZA.sql` - Vistas y funciones SQL
2. ✅ `lib/services/tiempos_service.dart` - Servicio Flutter (opcional, no usado actualmente)
3. ✅ `PATCH_PRODUCCION_SERVICE_TIEMPOS.dart` - Nuevo método para `produccion_service.dart`
4. ✅ `INSTRUCCIONES_IMPLEMENTAR_TIEMPOS.md` - Este archivo

---

## 🚀 **PASOS A SEGUIR:**

### **PASO 1: Ejecutar el script SQL** (EN SUPABASE)

1. Abrir Supabase SQL Editor: https://supabase.com/dashboard/project/szoywhtkilgvfrczuyqn/sql
2. Copiar y pegar el contenido de: `SISTEMA_TIEMPOS_COMPLETO_TRAZA_V2.sql` ⚠️ **USAR V2**
3. Hacer clic en **Run** (▶️)
4. Verificar que se crearon correctamente:
   - ✅ Función `calcular_minutos_inicio_tardio()` (con soporte para turnos)
   - ✅ Función `calcular_minutos_hora_extra()` (con soporte para turnos)
   - ✅ Vista `v_tiempos_diarios`
   - ✅ Vista `v_tiempos_mensuales`
   - ✅ Vista `v_resumen_tiempos_app`

**Verificación rápida:**

```sql
-- Debe mostrar datos de Alberto Escalona (si tiene órdenes)
SELECT * FROM v_resumen_tiempos_app
WHERE rut_tecnico = '26402839-6'
  AND mes = 1
  AND anio = 2026;
```

Resultado esperado:
```
minutos_inicio_tardio | horas_inicio_tardio | dias_con_inicio_tardio | minutos_hora_extra | horas_extra | dias_con_hora_extra
----------------------|---------------------|------------------------|--------------------|--------------|--------------------|
           120        |         2.00        |            5           |         540        |      9.00    |          10
```

---

### **PASO 2: Actualizar produccion_service.dart**

1. Abrir: `C:\Users\Usuario\trazabox\lib\services\produccion_service.dart`
2. Buscar el método `obtenerMetricasTiempo()` (línea ~1504)
3. **REEMPLAZAR TODO EL MÉTODO** con el código de `PATCH_PRODUCCION_SERVICE_TIEMPOS.dart`

**Antes:**
```dart
Future<Map<String, dynamic>> obtenerMetricasTiempo(
  String rutTecnico, {
  int? mes,
  int? anno,
}) async {
  // ... código muy largo y complejo con cálculos manuales ...
}
```

**Después:**
```dart
Future<Map<String, dynamic>> obtenerMetricasTiempo(
  String rutTecnico, {
  int? mes,
  int? anno,
}) async {
  // ... código simplificado que usa las vistas SQL ...
}
```

4. Guardar el archivo

---

### **PASO 3: Compilar y probar la app**

```bash
cd C:\Users\Usuario\trazabox

# Limpiar build anterior
flutter clean

# Obtener dependencias
flutter pub get

# Compilar APK
flutter build apk --release
```

---

### **PASO 4: Instalar y verificar**

1. Instalar APK en el dispositivo:
   ```bash
   adb install -r build\app\outputs\flutter-apk\app-release.apk
   ```

2. Abrir la app y navegar a **"Tu Mes"**

3. Verificar que aparezcan:
   - ⏰ **Inicio tardío**: Muestra "Xm" en lugar de "0m" (si tiene tardanzas)
   - ⏳ **Horas extras**: Muestra "Xm" en lugar de "0m" (si tiene horas extras)

---

## 🔍 **CÓMO VERIFICAR QUE FUNCIONA:**

### **Test 1: Ver inicio tardío en la app**

Si un técnico inició su primera orden del día después de las 9:45 (L-V) o 10:00 (Sáb), debe mostrar:

```
┌─────────────────────────────────┐
│ 🔔 Inicio tardío: 45m           │
│ ▼ (Expandir para ver detalle)  │
└─────────────────────────────────┘
```

Al expandir, debe mostrar:
```
05/01/26 - Inició a las 10:30 (45 min tarde)
07/01/26 - Inició a las 10:15 (30 min tarde)
```

### **Test 2: Ver horas extras en la app**

Si un técnico terminó órdenes después de las 18:30 (L-V) o 14:00 (Sáb), debe mostrar:

```
┌─────────────────────────────────┐
│ ⏰ Horas extras: 135m            │
│ ▼ (Expandir para ver detalle)  │
└─────────────────────────────────┘
```

Al expandir, debe mostrar (agrupado por semana):
```
SEMANA 1 (2 días, 61 min)
  05/01/26 - Terminó a las 20:15 (61 min)

SEMANA 2 (1 día, 35 min)
  12/01/26 - Terminó a las 19:05 (35 min)
```

---

## 🐛 **TROUBLESHOOTING:**

### **Problema 1: La app sigue mostrando 0m**

**Causa:** Las vistas SQL no se crearon correctamente o no hay datos.

**Solución:**
1. Ejecutar en Supabase:
   ```sql
   SELECT * FROM v_resumen_tiempos_app LIMIT 5;
   ```
2. Si no devuelve nada, revisar:
   ```sql
   SELECT * FROM v_tiempos_diarios LIMIT 5;
   ```
3. Si aún no hay datos, verificar que existan órdenes con `hora_inicio` y `hora_fin`:
   ```sql
   SELECT COUNT(*) 
   FROM produccion 
   WHERE hora_inicio IS NOT NULL 
     AND hora_inicio != ''
     AND estado = 'Completado';
   ```

### **Problema 2: Error de compilación en Flutter**

**Causa:** Sintaxis incorrecta al pegar el código.

**Solución:**
1. Verificar que se copió TODO el método `obtenerMetricasTiempo()`
2. Verificar que las llaves `{ }` estén balanceadas
3. Ejecutar: `flutter analyze`
4. Corregir errores mostrados

### **Problema 3: "Column doesn't exist" en Supabase**

**Causa:** La vista no se creó correctamente.

**Solución:**
1. Eliminar vistas existentes:
   ```sql
   DROP VIEW IF EXISTS v_resumen_tiempos_app CASCADE;
   DROP VIEW IF EXISTS v_tiempos_mensuales CASCADE;
   DROP VIEW IF EXISTS v_tiempos_diarios CASCADE;
   DROP FUNCTION IF EXISTS calcular_minutos_inicio_tardio CASCADE;
   ```
2. Volver a ejecutar `SISTEMA_TIEMPOS_COMPLETO_TRAZA.sql`

---

## 📊 **QUERIES ÚTILES PARA DEBUG:**

### **Ver inicio tardío de un técnico en Enero:**

```sql
SELECT 
    fecha_trabajo,
    nombre_dia,
    primera_orden_hora,
    minutos_inicio_tardio,
    ordenes_completadas
FROM v_tiempos_diarios
WHERE rut_tecnico = '26402839-6'
  AND EXTRACT(MONTH FROM fecha_completa) = 1
  AND EXTRACT(YEAR FROM fecha_completa) = 2026
  AND minutos_inicio_tardio > 0
ORDER BY fecha_completa;
```

### **Ver horas extras de un técnico en Enero:**

```sql
SELECT 
    fecha_trabajo,
    nombre_dia,
    ultima_orden_hora,
    minutos_hora_extra,
    ordenes_completadas
FROM v_tiempos_diarios
WHERE rut_tecnico = '26402839-6'
  AND EXTRACT(MONTH FROM fecha_completa) = 1
  AND EXTRACT(YEAR FROM fecha_completa) = 2026
  AND minutos_hora_extra > 0
ORDER BY fecha_completa;
```

### **Ver resumen mensual:**

```sql
SELECT * FROM v_resumen_tiempos_app
WHERE rut_tecnico = '26402839-6'
  AND mes = 2
  AND anio = 2026;
```

---

## ✅ **CHECKLIST FINAL:**

- [ ] **PASO 1:** Script SQL ejecutado correctamente en Supabase
- [ ] **PASO 2:** Verificado que las vistas devuelven datos
- [ ] **PASO 3:** Método `obtenerMetricasTiempo()` reemplazado en `produccion_service.dart`
- [ ] **PASO 4:** App compilada sin errores (`flutter build apk --release`)
- [ ] **PASO 5:** APK instalado en dispositivo
- [ ] **PASO 6:** Verificado que muestra inicio tardío correctamente
- [ ] **PASO 7:** Verificado que muestra horas extras correctamente
- [ ] **PASO 8:** Al expandir las tarjetas, se ve el detalle por día/semana

---

## 🎉 **RESULTADO ESPERADO:**

```
┌──────────────────────────────────────┐
│     BONO DE PRODUCCIÓN FEBRERO       │
│       01/Enero - 31/Enero            │
├──────────────────────────────────────┤
│                                      │
│  Días PX-0: 0                        │
│                                      │
│  Tu posición: #4 de 30               │
│  6.1 RGU/día                         │
│                                      │
│  ⏱️ Tiempos del mes                  │
│                                      │
│  48m Prom/Orden | 5.6 Órdenes/Día   │
│                                      │
│  🔔 Inicio tardío: 120m ▼            │  ← ¡CORREGIDO!
│                                      │
│  ⏰ Horas extras: 540m ▼              │  ← ¡CORREGIDO!
│                                      │
│  📊 Distribución de la jornada       │
│  ▓▓▓▓▓▓▓░░░                          │
│  Trabajando: 79h 47m | Ocio: 0m     │
│  Ruta: 15h 30m                       │
└──────────────────────────────────────┘
```

---

**¿Listo para ejecutar? 🚀**

Si encuentras algún error, revisa la sección de **TROUBLESHOOTING** o ejecuta las queries de **DEBUG**.

