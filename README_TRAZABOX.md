# 📱 TrazaBox

**App Flutter para gestión de alertas de fibra óptica**  
Desarrollado para **TRAZA**

---

## 🎯 Proyecto

Esta es una réplica exacta de "Agente de Desconexiones" personalizada para TRAZA.

**Proyecto base:** `agente_desconexiones`  
**Fecha de replicación:** 2026-02-03

---

## ⚙️ Configuración Actual

### **Supabase**
- **URL:** `https://qbryjrkzhvkxusjtwhra.supabase.co`
- **Project ID:** `qbryjrkzhvkxusjtwhra`
- **Configurado en:** `lib/config/supabase_config.dart`

### **Identidad**
- **Nombre de la app:** TrazaBox
- **Empresa:** TRAZA
- **Package Android:** `com.traza.trazabox`
- **Colors:** Mantenidos de Creaciones Tecnológicas (por ahora)

### **ElevenLabs**
- **Agent ID:** Compartido con Creaciones Tecnológicas
- **Configurado en:** `lib/constants/app_constants.dart`

---

## ✅ Cambios Realizados

### **1. Configuración de proyecto**
- ✅ `pubspec.yaml` - Nombre cambiado a "trazabox"
- ✅ `lib/config/supabase_config.dart` - Credenciales de Supabase TRAZA
- ✅ `lib/constants/app_constants.dart` - Nombre de app y empresa

### **2. Configuración Android**
- ✅ `android/app/build.gradle.kts` - applicationId: `com.traza.trazabox`
- ✅ `android/app/src/main/AndroidManifest.xml` - Label: "TrazaBox"

### **3. Código de la app**
- ✅ Toda la estructura de código Flutter copiada
- ✅ Todas las pantallas, servicios y modelos intactos
- ✅ Conectado a Supabase proyecto TRAZA

---

## 📋 Próximos Pasos

### **Fase 1: Sistema de Bonos TRAZA** ✅
**Script:** `SISTEMA_BONOS_TRAZA_COMPLETO.sql`

✅ Tablas creadas:
   - `tipos_orden` - Catálogo de tipos con puntos RGU
   - `escala_ftth` - Matriz 27×12 (RGU × Calidad)
   - `escala_ntt` - Matriz 29×9 (Actividades × Calidad)
   - `escala_hfc` - Pendiente implementación completa
   - `produccion_traza` - Órdenes de trabajo
   - `calidad_traza` - Reiteraciones
   - `pagos_traza` - Bonos calculados

✅ Funciones SQL:
   - `obtener_puntos_rgu()` - Puntos según tipo de orden
   - `obtener_bono_ftth()` - Bono FTTH (matriz)
   - `obtener_bono_ntt()` - Bono NTT (matriz)

✅ Vistas:
   - `v_pagos_traza` - Vista de bonos con campos adicionales

📝 Documentación:
   - `GUIA_SISTEMA_BONOS_TRAZA.md` - Guía completa
   - `EJEMPLO_USO_BONOS_TRAZA.sql` - Ejemplos de uso

⏳ Pendiente:
   - Función de cálculo automático mensual
   - Trigger para actualizar puntos RGU
   - Integración con AppScript

### **Fase 2: Personalización Visual** (Pendiente)
1. Cambiar logo de la app
2. Ajustar colores corporativos de TRAZA (si difieren)
3. Actualizar splash screen

### **Fase 3: Configuración de Servicios** (Pendiente)
1. Configurar API de datos (similar a Kepler)
2. Configurar AppScript que dispara datos diariamente
3. Verificar integración con ElevenLabs

### **Fase 4: Testing** (Pendiente)
1. Probar autenticación
2. Probar todas las pantallas
3. Probar conexión a Supabase
4. Probar cálculo de bonos
5. Probar notificaciones

### **Fase 5: Compilación** (Pendiente)
1. Compilar APK de prueba
2. Probar en dispositivo real
3. Compilar APK release

---

## 🚀 Cómo Ejecutar

```bash
# Navegar al proyecto
cd C:\Users\Usuario\trazabox

# Instalar dependencias
flutter pub get

# Ejecutar en modo debug
flutter run

# Compilar APK release
flutter build apk --release
```

---

## 📊 Fuente de Datos

**Origen:** AppScript dispara datos diariamente a Supabase proyecto TRAZA  
**Tipo:** Similar a API Kepler  
**Datos:** Órdenes de trabajo, marcas de asistencia, alertas, producción, calidad

---

## 🔗 Proyectos Relacionados

- **Proyecto original:** `C:\Users\Usuario\agente_desconexiones`
- **Dashboard web:** `C:\Users\Usuario\agente_desconexiones\web\dashboard_tecnicos.html`

---

## 📝 Notas

- Esta es una réplica exacta funcional y gráfica
- Los colores se mantendrán los mismos hasta recibir especificaciones de TRAZA
- El agente de voz CREA es compartido entre ambas empresas
- La base de datos es completamente independiente (Supabase proyecto TRAZA)

---

**Última actualización:** 2026-02-03  
**Estado:** Estructura replicada ✅ | Base de datos pendiente ⏳

