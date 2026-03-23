# 🚨 Agente de Desconexiones

**App Flutter para gestión de alertas de fibra óptica**  
Desarrollado para **Creaciones Tecnológicas**

---

## 📋 Descripción

Aplicación móvil que permite a técnicos y supervisores gestionar alertas de desconexión en CTOs (Cajas de Terminación Óptica) de fibra óptica, integrada con el panel Kepler y el agente de voz CREA.

---

## ✨ Características

### 👷 Rol Técnico
- Recibe notificaciones push con alarma insistente
- Visualiza detalles de la alerta (CTO, pelo, OT, valores)
- Puede **Atender** o **Postergar** (1 vez, 5 min) la alerta
- Conversación con agente de voz CREA vía ElevenLabs
- Captura de fotos georeferenciadas (casos de churn)
- Escalamiento automático a supervisor (3 min sin respuesta)

### 👔 Rol Supervisor
- Recibe alertas escaladas
- Visualiza historial y estadísticas
- Gestión de casos especiales (CTO dañada, terceros)

### 🤖 Agente CREA
- Informa al técnico sobre la desconexión
- Monitorea progreso (consulta cada 20 min)
- Verifica regularización en panel Kepler
- Manejo de excepciones (churn, CTO dañada, terceros)

---

## 🔧 Configuración

### 1. Firebase
```bash
# Instalar FlutterFire CLI
dart pub global activate flutterfire_cli

# Configurar Firebase
flutterfire configure
```

### 2. ElevenLabs
Actualizar en `lib/constants/app_constants.dart`:
```dart
static const String elevenLabsAgentId = 'TU_AGENT_ID';
static const String elevenLabsVoiceId = 'TU_VOICE_ID';
```

### 3. API Kepler
Actualizar URL base en `lib/constants/app_constants.dart`:
```dart
static const String apiBaseUrl = 'https://tu-api-kepler.com';
```

### 4. Sonido de Alerta
- Android: Copiar `alerta_urgente.mp3` a `android/app/src/main/res/raw/`
- iOS: Copiar `alerta_urgente.caf` a `ios/Runner/`

### 5. Fuentes
Descargar Poppins de [Google Fonts](https://fonts.google.com/specimen/Poppins) y copiar a `assets/fonts/`

---

## 📦 Dependencias Principales

| Paquete | Uso |
|---------|-----|
| `firebase_messaging` | Notificaciones push |
| `flutter_local_notifications` | Notificaciones locales con sonido |
| `elevenlabs_flutter` | SDK del agente de voz |
| `geolocator` | Geolocalización |
| `image_picker` | Captura de fotos |
| `provider` | Estado de la app |

---

## 🚀 Ejecución

```bash
# Instalar dependencias
flutter pub get

# Ejecutar en modo debug
flutter run

# Compilar APK release
flutter build apk --release
```

---

## 📦 Build & Deploy

### Comandos Rápidos (Makefile)

```bash
# Ver todos los comandos disponibles
make help

# Build
make build          # Compilar APK release
make clean          # Limpiar artefactos de build

# Versionado
make version        # Ver versión actual
make bump           # Incrementar número de build
make bump-patch     # Incrementar patch (1.0.0 -> 1.0.1)
make bump-minor     # Incrementar minor (1.0.0 -> 1.1.0)

# Deploy a Supabase
make upload         # Subir APK existente
make deploy         # Bump + build + upload
make deploy-patch   # Deploy con patch bump
NOTES="Bug fixes" make deploy  # Con notas de release
```

### Configuración de Deploy

1. Crear archivo `.env` con credenciales de Supabase:
```bash
cp .env.example .env
# Editar .env con tu SUPABASE_SERVICE_KEY
```

2. El bucket `app-updates` debe ser público en Supabase Storage

3. Archivos en Supabase:
   - `version.json` - Metadata de versión
   - `trazabox.apk` - APK compilado

---

## 📡 Webhook desde Kepler

El panel Kepler debe enviar alertas con la siguiente estructura:

```json
{
  "nombre_tecnico": "Juan Pérez",
  "telefono_tecnico": "+56912345678",
  "numero_ot": "OT-12345",
  "access_id": "ACC-67890",
  "nombre_cto": "CTO-NORTE-01",
  "numero_pelo": "P-05",
  "valor_consulta1": 0.85,
  "tipo_alerta": "desconexion"
}
```

### Tipos de Alerta
- `desconexion` - Desconexión estándar
- `churn` - Requiere fotos georeferenciadas
- `cto_danada` - Escala automáticamente a supervisor
- `terceros_en_cto` - Escala automáticamente a supervisor

---

## 📂 Estructura del Proyecto

```
lib/
├── constants/        # Colores, constantes
├── models/           # Modelos de datos
├── providers/        # Estado con Provider
├── screens/          # Pantallas
├── services/         # Servicios (API, notificaciones, CREA)
├── utils/            # Utilidades
├── widgets/          # Widgets reutilizables
└── main.dart         # Punto de entrada
```

---

## 👥 Equipo

**Creaciones Tecnológicas**

---

## 📄 Licencia

Propietario - Todos los derechos reservados
