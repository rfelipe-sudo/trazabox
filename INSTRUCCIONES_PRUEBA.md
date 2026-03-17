# 🧪 Instrucciones para Probar TrazaBox

## ✅ Estado Actual

```
✅ Proyecto copiado
✅ Dependencias instaladas
✅ Supabase configurado (proyecto TRAZA)
✅ Base de datos creada (bonos + usuarios)
✅ 13 usuarios de prueba listos
```

---

## 🚀 Ejecutar la App

### **Opción A: Desde Visual Studio Code / Cursor**
1. Abre el proyecto en VS Code/Cursor
2. Conecta tu dispositivo Android o inicia un emulador
3. Presiona `F5` o haz clic en "Run" → "Start Debugging"

### **Opción B: Desde Terminal**
```bash
cd C:\Users\Usuario\trazabox
flutter run
```

### **Opción C: Compilar APK directamente**
```bash
cd C:\Users\Usuario\trazabox
flutter build apk --debug
```
El APK quedará en: `build\app\outputs\flutter-apk\app-debug.apk`

---

## 🔐 Credenciales de Prueba

### **Para primer login usa:**
```
RUT: 150000001
(sin puntos ni guión)

Nombre: Juan Pérez (FTTH)
Rol: Técnico
```

### **Otros usuarios disponibles:**
- Admin: `111111111`
- Supervisor: `123456789`
- Técnico FTTH: `150000001` a `150000005`
- Técnico NTT: `160000001` a `160000005`

Ver archivo `CREDENCIALES_PRUEBA.md` para lista completa.

---

## 📊 Qué Esperar

### **✅ Debería funcionar:**
- Login con RUT
- Pantalla de inicio
- Navegación entre pantallas
- Conexión a Supabase

### **⚠️ Puede fallar (es normal):**
- Pantalla "Tu Mes" (datos de bonos)
- Pantalla de Producción (órdenes)
- Pantalla de Calidad (reiteraciones)
- Rankings

**Motivo:** Las tablas de Creaciones (`produccion_crea`, `calidad_crea`) no existen en TRAZA. Necesitamos adaptar el código para usar las nuevas tablas (`produccion_traza`, `calidad_traza`).

---

## 🐛 Errores Comunes y Soluciones

### **Error 1: "relation produccion_crea does not exist"**
✅ **Normal:** La app busca tablas de Creaciones que no existen en TRAZA.
🔧 **Solución:** Adaptar código (siguiente fase).

### **Error 2: "No se encontraron datos"**
✅ **Normal:** No hay órdenes ni datos de producción aún.
🔧 **Solución:** Crear script de integración con AppScript.

### **Error 3: Pantalla en blanco después de login**
⚠️ **Problema:** Puede ser error de autenticación o datos faltantes.
🔧 **Solución:** Revisar logs en consola.

### **Error 4: "Failed to load data"**
✅ **Normal:** Algunas pantallas intentan cargar datos que aún no existen.
🔧 **Solución:** Es esperado, continuamos con adaptación.

---

## 📝 Checklist de Prueba

Durante la prueba, verificar:

### **Login y Autenticación:**
- [ ] Login con RUT funciona
- [ ] Muestra nombre del técnico
- [ ] Navega a pantalla principal

### **Navegación:**
- [ ] Drawer lateral se abre
- [ ] Puede cambiar entre pantallas
- [ ] Botones responden

### **Pantallas Críticas:**
- [ ] Home Screen carga
- [ ] "Tu Mes" (puede fallar - OK)
- [ ] Producción (puede fallar - OK)
- [ ] Calidad (puede fallar - OK)
- [ ] Configuración

### **Errores a Reportar:**
- [ ] Anotar qué pantallas cargan OK
- [ ] Anotar qué pantallas fallan
- [ ] Copiar mensajes de error de consola

---

## 🔍 Ver Logs de Consola

Los logs te dirán exactamente qué está fallando:

```bash
flutter run --verbose
```

Buscar líneas con:
- ❌ `ERROR:`
- ⚠️ `WARNING:`
- 🔍 `[DEBUG]`

---

## 📸 Capturas Útiles

Si puedes, toma capturas de:
1. Pantalla de login exitoso
2. Pantalla principal (home)
3. Errores que aparezcan
4. Logs de consola con errores

---

## 🎯 Objetivo de Esta Prueba

**No es necesario que todo funcione.** El objetivo es:
1. ✅ Verificar que la app compila
2. ✅ Verificar que login funciona
3. ✅ Identificar qué necesita adaptación
4. ✅ Priorizar siguientes pasos

---

## 📋 Después de Probar

Una vez que hayas probado, comparte:
1. ¿Llegaste al login? ✅ / ❌
2. ¿Login funcionó? ✅ / ❌
3. ¿Qué pantallas cargaron OK?
4. ¿Qué errores viste en consola?

Con esa info, procederé a:
- Adaptar código para tablas TRAZA
- Crear script de integración AppScript
- Poblar datos de prueba

---

## 🚀 ¿Listo para Probar?

Ejecuta:
```bash
flutter run
```

O compila el APK:
```bash
flutter build apk --debug
```

---

**Estado:** Listo para prueba inicial
**Tiempo estimado:** 10-15 minutos

