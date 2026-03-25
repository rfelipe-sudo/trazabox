# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Resumen del Proyecto

TrazaBox es una app Flutter para gestionar alertas de desconexión de fibra óptica en CTOs (Cajas de Terminación Óptica). Se integra con el panel Kepler y un agente de voz llamado CREA (vía ElevenLabs).

**Roles:**
- Técnico: Recibe alertas, atiende/posterga, captura fotos georeferenciadas
- ITO: Similar a técnico con acceso adicional a "Mi Equipo"
- Supervisor: Recibe alertas escaladas, gestiona equipo, ve estadísticas
- Bodeguero: Gestión de materiales y bodega

## Comandos

```bash
# Desarrollo
flutter pub get              # Instalar dependencias
flutter run                  # Ejecutar en modo debug
flutter test                 # Ejecutar tests
flutter doctor -v            # Verificar entorno

# Build
flutter build apk --release  # Compilar APK release
flutter build apk --split-per-abi --release  # APKs por ABI (más pequeños)
flutter clean                # Limpiar artefactos de build

# Makefile (atajos)
make build          # Compilar APK release
make version        # Ver versión actual (1.2.1+4)
make bump           # Incrementar número de build
make deploy         # Bump + build + upload a Supabase
make run-dev        # Ejecutar app en debug
make doctor         # flutter doctor -v
```

## Configuración de Deploy

1. Copiar `.env.example` a `.env` y agregar `SUPABASE_SERVICE_KEY`
2. El bucket `app-updates` en Supabase Storage debe ser público
3. Archivos desplegados: `version.json` (metadata), `trazabox.apk` (binario)

## Arquitectura

```
lib/
├── config/           # SupabaseConfig (URL y anon key)
├── constants/        # AppConstants, AppColors, CreaMessages
├── features/         # Módulos por feature
│   └── transferencias/  # models/, screens/, services/
├── models/           # Alerta, Usuario, CalidadTecnico, etc.
├── providers/        # Estado global con Provider
├── screens/          # UI por rol (supervisor/) y generales
├── services/         # Lógica de negocio y APIs externas
├── utils/            # FeriadosChile, pageTransitions
├── widgets/          # Componentes reutilizables
└── main.dart         # Punto de entrada + inicialización
```

### Servicios Principales

| Servicio | Propósito |
|----------|-----------|
| `SupabaseService` | Backend (DB + Storage). Acceso global via `supabaseService` |
| `KeplerApiService` | API del panel Kepler para alertas |
| `CreaAgentService` / `ElevenLabsService` | Agente de voz CREA |
| `LocalNotificationService` | Notificaciones locales con sonido custom |
| `DeteccionCaminataService` | Activity recognition para anti-fraude |
| `PorticoDetectorService` | Detección de pórticos |
| `AyudaService` | Sistema de solicitudes de ayuda |
| `ProduccionService` | Métricas de producción y bonos |
| `UpdateService` | Auto-actualización desde Supabase |
| `ChurnService` | Gestión de fotos para casos churn |
| `EstadoSupervisorService` | Estado del supervisor |

### Estado Global (Provider)

- `AuthProvider`: Autenticación, registro de dispositivo, rol del usuario
- `AlertasProvider`: Gestión de alertas pendientes
- `ChurnService`, `AyudaService`, `EstadoSupervisorService`: También son ChangeNotifiers

### Flujo de Inicialización (main.dart)

1. `Supabase.initialize()` - crítico, bloquea UI si falla
2. `runApp()` - muestra SplashScreen inmediatamente
3. `_inicializarServiciosEnBackground()` - no bloquea UI:
   - Notificaciones (LocalNotificationService, NotificationService)
   - Activity recognition (permisos + listeners)
   - Detección de caminata (anti-fraude)
   - PorticoDetectorService (solo para rol técnico)
   - AlertaContextoService

### Sistema Anti-Fraude

El app monitorea actividad del técnico durante trabajos activos:
- **No se bajó**: Alerta si 0 pasos después de 5 min en ubicación
- **Fuera de rango**: Alerta si >200m del sitio de trabajo
- **En movimiento**: Alerta si velocidad >20 km/h

Las alertas se envían a `alertas_fraude` en Supabase via `supabaseService.enviarAlertaFraude()`.

## Archivos de Configuración

| Archivo | Contenido |
|---------|-----------|
| `lib/constants/app_constants.dart` | URLs API, timeouts, ElevenLabs config |
| `lib/config/supabase_config.dart` | URL y anon key de Supabase |
| `pubspec.yaml` | Dependencias y versión (`version: X.Y.Z+BUILD`) |

## Constantes de Tiempo (AppConstants)

- `tiempoEscalamientoSegundos`: 180s (3 min → escalar a supervisor)
- `tiempoPostergacionSegundos`: 300s (5 min snooze)
- `tiempoConsultaProgresoSegundos`: 1200s (20 min check-in CREA)
- `tiempoMaximoAtencionSegundos`: 3600s (1 hora máximo)

## Webhook desde Kepler

```json
{
  "nombre_tecnico": "Juan Pérez",
  "telefono_tecnico": "+56912345678",
  "numero_ot": "OT-12345",
  "access_id": "ACC-67890",
  "nombre_cto": "CTO-NORTE-01",
  "numero_pelo": "P-05",
  "valor_consulta1": 0.85,
  "tipo_alerta": "desconexion"  // | churn | cto_danada | terceros_en_cto
}
```

## Tablas Supabase Principales

- `tecnicos_registro` - Registro RUT ↔ dispositivo
- `alertas_fraude` - Alertas del sistema anti-fraude
- `alertas_cto` - Alertas de CTOs
- `fotos_churn` - Fotos georeferenciadas de churn
- `tecnicos_ubicacion` - Tracking en tiempo real (tipo Uber)
- `produccion_traza`, `calidad_traza`, `pagos_traza` - Sistema de bonos
