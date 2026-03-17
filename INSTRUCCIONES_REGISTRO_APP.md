# 📱 INSTRUCCIONES PARA REGISTRARSE EN TRAZABOX

## 🎯 Paso 1: Ejecutar script en Supabase

1. Ve a **Supabase TRAZA**: https://supabase.com/dashboard/project/qbryjrkzhvkxusjtwhra/sql/new

2. Abre el archivo: `C:\Users\Usuario\trazabox\INSERT_TECNICOS_PRUEBA.sql`

3. **Copia todo el contenido** del archivo

4. **Pégalo** en el SQL Editor de Supabase

5. Haz clic en **"Run"** para ejecutar

✅ Esto insertará 7 técnicos de prueba en la tabla `produccion_traza`

---

## 🎯 Paso 2: Recompilar la app

En PowerShell, ejecuta:

```powershell
cd C:\Users\Usuario\trazabox
flutter clean
flutter pub get
flutter build apk --release
```

---

## 🎯 Paso 3: Instalar y registrarse

1. **Desinstala** la versión anterior de TrazaBox

2. **Instala** el nuevo APK:
   ```
   C:\Users\Usuario\trazabox\build\app\outputs\flutter-apk\app-release.apk
   ```

3. **Abre** la app TrazaBox

4. En la pantalla de registro, ingresa:

### 🔑 Credenciales de prueba:

| RUT | Nombre | Tecnología | Teléfono |
|-----|--------|-----------|----------|
| **12345678-9** | Juan Pérez González | FTTH | +56912345678 |
| **11111111-1** | María López Silva | NTT | +56987654321 |
| **22222222-2** | Carlos Ramírez Torres | FTTH (Supervisor) | +56911111111 |
| **33333333-3** | Andrea Muñoz Díaz | FTTH | +56922222222 |
| **44444444-4** | Roberto Castro Vega | FTTH | +56933333333 |
| **55555555-5** | Claudia Soto Rojas | NTT | +56944444444 |
| **66666666-6** | Diego Herrera Ponce | NTT | +56955555555 |

---

## 📝 Flujo de registro:

1. **Ingresa el RUT** (ej: `12345678-9`)
   - La app lo validará contra la base de datos
   - Si existe, mostrará el nombre del técnico

2. **Ingresa el teléfono** (ej: `+56912345678`)
   - Puede ser cualquier número válido

3. Haz clic en **"INGRESAR"**

4. ✅ El dispositivo quedará registrado permanentemente

---

## ⚠️ IMPORTANTE:

- **NO hay contraseña** en este sistema
- El registro es **por dispositivo** (Android ID)
- Una vez registrado, no necesitas volver a ingresar credenciales
- Para probar con otro usuario, limpia los datos de la app o usa otro dispositivo

---

## 🔧 Si algo falla:

Revisa los logs ejecutando:
```powershell
flutter run --release
```

Y observa los mensajes en la consola.

