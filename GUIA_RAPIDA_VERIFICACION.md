# 🚀 Guía Rápida: Verificación y Compilación

## ✅ Cambios Aplicados

Todos los archivos ahora apuntan a:
- **Tabla**: `produccion` (no `produccion_traza`)
- **Supabase**: `szoywhtkilgvfrczuyqn.supabase.co`

### Archivos Actualizados:
1. ✅ `lib/config/supabase_config.dart` - Nueva URL y Key
2. ✅ `lib/services/tecnico_service.dart` - Usa tabla `produccion`
3. ✅ `lib/services/produccion_service.dart` - Usa tabla `produccion`
4. ✅ `APPSCRIPT_TRAZA_FINAL.js` - Inserta en tabla `produccion`
5. ✅ `VERIFICAR_DATOS_REALES.sql` - Consultas actualizadas

---

## 📋 Paso 1: Verificar Datos en Supabase

### 1.1 Abrir Supabase
- URL: https://supabase.com/dashboard
- Proyecto: `szoywhtkilgvfrczuyqn`
- Ir a: **SQL Editor**

### 1.2 Ejecutar esta consulta:

```sql
-- Ver técnicos disponibles
SELECT 
    rut_tecnico,
    tecnico,
    COUNT(*) as ordenes_completadas,
    ROUND(SUM(rgu_total)::numeric, 2) as rgu_total
FROM produccion
WHERE estado = 'Completado'
  AND fecha_trabajo LIKE '%/01/26%'
  AND rut_tecnico IS NOT NULL
GROUP BY rut_tecnico, tecnico
ORDER BY rgu_total DESC
LIMIT 10;
```

### 1.3 ¿Qué esperar?

**✅ SI HAY DATOS:**
```
rut_tecnico      | tecnico           | ordenes | rgu_total
-----------------|-------------------|---------|----------
12345678-9       | Kenny Ramirez B   | 15      | 25.50
18765432-1       | María López       | 12      | 20.00
```

→ **Copia un RUT** y pasa al Paso 2

**❌ SI NO HAY DATOS:**
```
0 rows returned
```

→ Necesitas ejecutar el AppScript primero (ver Paso 1.4)

### 1.4 Si no hay datos: Ejecutar AppScript

1. Abre Google Apps Script
2. Pega el código de `APPSCRIPT_TRAZA_FINAL.js`
3. Ejecuta la función: `pruebaProduccionTRAZA()`
4. Espera a que termine (verás logs de progreso)
5. Vuelve a ejecutar la consulta 1.2

---

## 📱 Paso 2: Compilar la App

Una vez que tengas un RUT válido:

```bash
cd C:\Users\Usuario\trazabox
flutter clean
flutter pub get
flutter build apk --release
```

**Ubicación del APK:**
```
C:\Users\Usuario\trazabox\build\app\outputs\flutter-apk\app-release.apk
```

---

## 🧪 Paso 3: Probar el Registro

1. **Instalar APK** en tu dispositivo Android
2. **Abrir TrazaBox**
3. **Registrarte:**
   - **RUT**: [El RUT que copiaste del Paso 1.2]
   - **Teléfono**: 912345678 (cualquier número)
4. **Presionar "Continuar"**

### ¿Qué debería pasar?

**✅ Si el RUT existe:**
- ✅ Registro exitoso
- ✅ La app te lleva a la pantalla principal
- ✅ En "Tu Mes" verás tus datos de producción

**❌ Si el RUT no existe:**
- ❌ Error: "RUT no encontrado en producción"
- → Verifica que el RUT esté correcto
- → Ejecuta nuevamente la consulta del Paso 1.2

---

## 🐛 Solución de Problemas

### Error: "relation produccion does not exist"
→ La tabla no existe en Supabase
→ Ejecuta el AppScript para crear y poblar los datos

### Error: "0 rows returned" al consultar
→ No hay datos cargados
→ Ejecuta `pruebaProduccionTRAZA()` en el AppScript

### Error: "RUT no encontrado" en la app
→ El RUT ingresado no está en la tabla `produccion`
→ Usa un RUT de la consulta del Paso 1.2

### Error de compilación Flutter
→ Ejecuta: `flutter clean && flutter pub get`
→ Verifica que tengas Flutter 3.35.6 o superior

---

## 📊 Verificaciones Adicionales

### Ver estructura de la tabla:
```sql
SELECT column_name, data_type 
FROM information_schema.columns
WHERE table_name = 'produccion'
ORDER BY ordinal_position;
```

### Ver total de registros:
```sql
SELECT COUNT(*) as total FROM produccion;
```

### Ver últimos registros insertados:
```sql
SELECT 
    rut_tecnico,
    tecnico,
    fecha_trabajo,
    orden_trabajo,
    estado,
    rgu_total
FROM produccion
ORDER BY created_at DESC
LIMIT 10;
```

---

## 🎯 Resumen de Comandos

```bash
# 1. Limpiar proyecto
cd C:\Users\Usuario\trazabox
flutter clean

# 2. Obtener dependencias
flutter pub get

# 3. Compilar APK
flutter build apk --release

# 4. Ubicación del APK
# C:\Users\Usuario\trazabox\build\app\outputs\flutter-apk\app-release.apk
```

---

## ✅ Checklist Final

- [ ] Ejecuté la consulta SQL y obtuve RUTs válidos
- [ ] Copié un RUT para usar en el registro
- [ ] Compilé la app sin errores
- [ ] Instalé el APK en mi dispositivo
- [ ] Me registré con el RUT copiado
- [ ] La app muestra mis datos de producción

---

**¿Todo listo?** Ejecuta el Paso 1.2 y compárteme los resultados. 🚀

