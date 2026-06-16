import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart' as activity_recognition;

import 'package:trazabox/constants/app_constants.dart';
import 'package:trazabox/constants/app_colors.dart';
import 'package:trazabox/config/supabase_config.dart';
import 'package:trazabox/providers/auth_provider.dart';
import 'package:trazabox/providers/alertas_provider.dart';
import 'package:trazabox/providers/alerta_provider.dart';
import 'package:trazabox/services/fcm_service.dart';
import 'package:trazabox/services/local_notification_service.dart';
import 'package:trazabox/services/alerta_contexto_service.dart';
import 'package:trazabox/services/churn_service.dart';
import 'package:trazabox/services/ayuda_service.dart';
import 'package:trazabox/services/sesion_dispositivo_service.dart';
import 'package:trazabox/services/supabase_service.dart';
import 'package:trazabox/screens/splash_screen.dart';
import 'package:trazabox/screens/dispositivo_bloqueado_screen.dart';
import 'package:trazabox/screens/registro_rut_screen.dart';
import 'package:trazabox/screens/registro_screen.dart';
import 'package:trazabox/screens/desbloqueo_app_screen.dart';
import 'package:trazabox/screens/home_screen.dart';
import 'package:trazabox/screens/asistente_cto_screen.dart';
import 'package:trazabox/screens/asistente_crea_terreno_screen.dart';
import 'package:trazabox/screens/mapa_calor_screen.dart';
import 'package:trazabox/screens/wifi_mapas_screen.dart';
import 'package:trazabox/screens/wifi_credenciales_screen.dart';
import 'package:trazabox/screens/wifi_cobertura_screen.dart';
import 'package:trazabox/screens/certificado_wifi_screen.dart';
import 'package:trazabox/screens/ayuda_terreno_screen.dart';
import 'package:trazabox/screens/speed_meter_screen.dart';
import 'package:trazabox/screens/fiber_microscope_screen.dart';
import 'package:trazabox/screens/mis_actividades_screen.dart';
import 'package:trazabox/screens/finalizar_orden_screen.dart';
import 'package:trazabox/screens/solicitud_material_screen.dart';
import 'package:trazabox/screens/supervisor/mi_equipo_screen.dart';
import 'package:trazabox/screens/supervisor/solicitudes_ayuda_screen.dart';
import 'package:trazabox/screens/supervisor/mi_actividad_screen.dart';
import 'package:trazabox/screens/supervisor/asistente_supervisor_screen.dart';
import 'package:trazabox/screens/supervisor/auditoria_prl_screen.dart';
import 'package:trazabox/screens/ast_workflow_screen.dart';
import 'package:trazabox/screens/ast_login_screen.dart';
import 'package:trazabox/services/estado_supervisor_service.dart';
import 'package:trazabox/services/notification_service.dart';
import 'package:trazabox/screens/bodeguero_menu_screen.dart';
import 'package:trazabox/services/deteccion_caminata_service.dart';
import 'package:trazabox/services/kepler_polling_service.dart';
import 'package:trazabox/services/alertas_cto_service.dart';
import 'package:trazabox/services/notificacion_service.dart';
import 'package:trazabox/services/alarm_audio_service.dart';
import 'package:trazabox/utils/session_manager.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Helper para acceder a Supabase desde cualquier lugar
final supabaseService = SupabaseService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // LATEST renderer: soporta el parámetro style: en GoogleMap widget.
  final mapsImpl = GoogleMapsFlutterPlatform.instance;
  if (mapsImpl is GoogleMapsFlutterAndroid) {
    mapsImpl.initializeWithRenderer(AndroidMapRenderer.latest);
  }

  // Firebase + FCM background handler ANTES de cualquier otra cosa async
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await FcmService.instance.init();
    print('✅ Firebase + FCM inicializados');
  } catch (e) {
    print('⚠️ [Main] Firebase no inicializado: $e');
  }

  try {
    final notificacionService = NotificacionService();
    await notificacionService.inicializar();
  } catch (e) {
    print('⚠️ [Main] Error inicializando NotificacionService: $e');
  }

  // Supabase es crítico — inicializar antes de la UI
  try {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
    print('✅ Supabase inicializado');
  } catch (e) {
    print('❌ [Main] Error inicializando Supabase: $e');
  }

  try {
    await _solicitarPermisos();
  } catch (e) {
    print('⚠️ [Main] Error solicitando permisos: $e');
  }

  try {
    _iniciarActivityRecognition();
  } catch (e) {
    print('⚠️ [Main] Error iniciando Activity Recognition: $e');
  }

  try {
    await _crearCanalNotificacionDeteccion();
  } catch (e) {
    print('⚠️ [Main] Error creando canal de notificación: $e');
  }

  if (AppConstants.monitoreoFraudeYAlertasCtoActivo) {
    try {
      final deteccionService = DeteccionCaminataService();
      await deteccionService.inicializar();
    } catch (e) {
      print('⚠️ [Main] Error inicializando DeteccionCaminataService: $e');
    }

    try {
      _configurarListenerAlertasAutomaticas();
    } catch (e) {
      print('⚠️ [Main] Error configurando listeners: $e');
    }

    try {
      final keplerPolling = KeplerPollingService();
      await keplerPolling.iniciar();
    } catch (e) {
      print('⚠️ [Main] Error iniciando KeplerPollingService: $e');
    }

    try {
      final alertasCTOService = AlertasCTOService();
      await alertasCTOService.iniciar();
    } catch (e) {
      print('⚠️ [Main] Error iniciando AlertasCTOService: $e');
    }
  } else {
    print('ℹ️ [Main] Monitoreo fraude / alertas CTO desactivado (AppConstants)');
  }

  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } catch (e) {
    print('⚠️ [Main] Error configurando orientación: $e');
  }

  try {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF0A1628),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  } catch (e) {
    print('⚠️ [Main] Error configurando estilo de barra: $e');
  }

  LocalNotificationService? notificationService;

  try {
    notificationService = LocalNotificationService();
    await notificationService.initialize();
  } catch (e) {
    print('⚠️ [Main] Error inicializando LocalNotificationService: $e');
  }

  try {
    await AlertaContextoService().initialize();
  } catch (e) {
    print('⚠️ [Main] Error inicializando AlertaContextoService: $e');
  }

  try {
    if (notificationService != null) {
      print('🔔 [Main] Cancelando todas las notificaciones pendientes...');
      try {
        await notificationService.cancelAllNotifications().timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            print('⚠️ [Main] Timeout cancelando notificaciones (continuando...)');
          },
        );
        print('✅ [Main] Todas las notificaciones canceladas');
      } catch (e) {
        print('⚠️ [Main] Error cancelando notificaciones: $e');
      }
    }

    try {
      final alarmAudio = AlarmAudioService();
      bool estaReproduciendo = false;
      try {
        estaReproduciendo = alarmAudio.estaReproduciendo;
      } catch (e) {
        print('⚠️ [Main] Error verificando estado de alarma: $e');
      }
      if (estaReproduciendo) {
        await alarmAudio.detenerAlarma().timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            print('⚠️ [Main] Timeout deteniendo alarma (continuando...)');
          },
        );
      }
    } catch (e) {
      print('⚠️ [Main] Error deteniendo alarma: $e');
    }
  } catch (e) {
    print('❌ [Main] Error crítico limpiando estado al iniciar: $e');
  }

  try {
    await NotificationService().init();
  } catch (e) {
    print('⚠️ [Main] NotificationService Ayuda: $e');
  }

  print('✅ [Main] Inicialización completada - Iniciando app...');
  await SessionManager.init();
  SesionDispositivoService.marcarInicioApp();
  runApp(const TrazaBoxApp());
}

/// Inicializar Activity Recognition en el main isolate
void _iniciarActivityRecognition() {
  try {
    final activityRecognition = activity_recognition.FlutterActivityRecognition.instance;

    activityRecognition.activityStream.listen((activity) {
      print('🏃 [Main] Actividad detectada: ${activity.type}');

      FlutterBackgroundService().invoke('actividadDetectada', {
        'tipo': activity.type.toString(),
        'confianza': activity.confidence.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      });
    }, onError: (e) {
      print('❌ [Main] Error Activity Recognition: $e');
    });

    print('✅ [Main] Activity Recognition iniciado');
  } catch (e) {
    print('❌ [Main] Error iniciando Activity Recognition: $e');
  }
}

/// Crear canal de notificación para el servicio de detección
Future<void> _crearCanalNotificacionDeteccion() async {
  try {
    final FlutterLocalNotificationsPlugin notifications =
        FlutterLocalNotificationsPlugin();

    const androidChannel = AndroidNotificationChannel(
      'deteccion_caminata',
      'Monitoreo de Actividad',
      description: 'Notificaciones del servicio de monitoreo de actividad',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );

    final androidImplementation = notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(androidChannel);
      print('✅ Canal de notificación creado: deteccion_caminata');
    }
  } catch (e) {
    print('⚠️ Error creando canal de notificación: $e');
  }
}

/// Solicitar permisos necesarios para detección de actividad
Future<void> _solicitarPermisos() async {
  try {
    final activityRecognition = activity_recognition.FlutterActivityRecognition.instance;
    final permission = await activityRecognition.checkPermission();

    final statusString = permission.toString();
    if (statusString.contains('DENIED') ||
        statusString.contains('denied') ||
        statusString.contains('NOT_DETERMINED')) {
      await activityRecognition.requestPermission();
    }
    print('✅ Permisos de Activity Recognition configurados');
  } catch (e) {
    print('⚠️ Error solicitando permisos: $e');
  }
}

/// Configurar listener para alertas automáticas desde el servicio en segundo plano
void _configurarListenerAlertasAutomaticas() {
  final service = FlutterBackgroundService();

  service.on('alertaAutomatica').listen((data) async {
    if (data == null) return;
    print('🚨 [Main] Alerta: Técnico no se bajó');

    await supabaseService.enviarAlertaFraude(
      ot: data['ot'] ?? '',
      tecnicoId: data['tecnico_id'] ?? '',
      nombreTecnico: data['nombre_tecnico'] ?? '',
      pasosRealizados: data['pasos_realizados'] ?? 0,
      distanciaRecorrida: (data['distancia_recorrida'] as num?)?.toDouble() ?? 0,
      razonesFallo: List<String>.from(data['razones_fallo'] ?? []),
      latitud: (data['latitud'] as num?)?.toDouble(),
      longitud: (data['longitud'] as num?)?.toDouble(),
      tipo: 'no_se_bajo',
    );
  });

  service.on('alertaFueraDeRango').listen((data) async {
    if (data == null) return;
    print('🚨 [Main] Alerta: Técnico fuera de rango');

    await supabaseService.enviarAlertaFraude(
      ot: data['ot'] ?? '',
      tecnicoId: data['tecnico_id'] ?? '',
      nombreTecnico: data['nombre_tecnico'] ?? '',
      pasosRealizados: 0,
      distanciaRecorrida: (data['distancia_desde_trabajo'] as num?)?.toDouble() ?? 0,
      razonesFallo: ['Fuera de rango: ${(data['distancia_desde_trabajo'] as num?)?.toStringAsFixed(0)}m (máx ${data['radio_maximo']}m)'],
      latitud: (data['latitud_tecnico'] as num?)?.toDouble(),
      longitud: (data['longitud_tecnico'] as num?)?.toDouble(),
      tipo: 'fuera_de_rango',
    );
  });

  service.on('alertaEnMovimiento').listen((data) async {
    if (data == null) return;
    print('🚨 [Main] Alerta: Técnico en movimiento');

    await supabaseService.enviarAlertaFraude(
      ot: data['ot'] ?? '',
      tecnicoId: data['tecnico_id'] ?? '',
      nombreTecnico: data['nombre_tecnico'] ?? '',
      pasosRealizados: 0,
      distanciaRecorrida: 0,
      razonesFallo: ['En movimiento: ${(data['velocidad_kmh'] as num?)?.toStringAsFixed(1)} km/h (máx ${data['velocidad_maxima']} km/h)'],
      latitud: (data['latitud'] as num?)?.toDouble(),
      longitud: (data['longitud'] as num?)?.toDouble(),
      tipo: 'en_movimiento',
    );
  });

  print('✅ Listeners de alertas configurados (no_se_bajo, fuera_de_rango, en_movimiento)');
}

class TrazaBoxApp extends StatelessWidget {
  const TrazaBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => AlertasProvider()),
        ChangeNotifierProvider<AlertaProvider>(
          create: (_) {
            final p = AlertaProvider()..initialize();
            FcmService.instance.setAlertaProvider(p);
            return p;
          },
        ),
        ChangeNotifierProvider(create: (_) => ChurnService()),
        ChangeNotifierProvider(create: (_) => AyudaService()),
        ChangeNotifierProvider(create: (_) => EstadoSupervisorService()),
      ],
      child: MaterialApp(
        navigatorKey: trazaboxNavigatorKey,
        navigatorObservers: [TrazaboxSesionNavigatorObserver()],
        title: 'TRAZABOX',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const SplashScreen(),
        builder: (context, child) =>
            _TrazaboxSesionLifecycleGuard(child: child ?? const SizedBox.shrink()),
        routes: {
          '/login': (context) => const RegistroRutScreen(),
          '/registro_rut': (context) => const RegistroRutScreen(),
          '/registro': (context) => const RegistroScreen(),
          '/dispositivo_bloqueado': (context) {
            final args = ModalRoute.of(context)?.settings.arguments;
            var estado = 'bloqueado';
            var mensaje = '';
            if (args is Map) {
              estado = args['estado']?.toString() ?? estado;
              mensaje = args['mensaje']?.toString() ?? '';
            }
            return DispositivoBloqueadoScreen(estado: estado, mensaje: mensaje);
          },
          '/desbloqueo': (context) => const DesbloqueoAppScreen(),
          '/home': (context) => const AppWrapper(),
          '/asistente-cto': (context) => const AsistenteCtoScreen(),
          '/asistente-crea-terreno': (context) => const AsistenteCreaTerrenoScreen(),
          '/mapa-calor': (context) => const MapaCalorScreen(),
          '/wifi-mapas': (context) => const WifiMapasScreen(),
          '/wifi-credenciales': (context) => const WifiCredencialesScreen(),
          '/wifi-cobertura': (context) => const WifiCoberturaScreen(),
          '/certificado-wifi': (context) {
            final args = ModalRoute.of(context)?.settings.arguments;
            final html = args is String ? args : null;
            return CertificadoWifiScreen(htmlOverride: html);
          },
          '/ayuda-terreno': (context) => const AyudaTerrenoScreen(),
          '/speed-meter': (context) => const SpeedMeterScreen(),
          '/microscope': (context) => const FiberMicroscopeScreen(),
          '/mis-actividades': (context) => const MisActividadesScreen(),
          '/finalizar-orden': (context) => const FinalizarOrdenScreen(),
          '/solicitud-material': (context) => const SolicitudMaterialScreen(),
          '/supervisor-equipo': (context) => const MiEquipoScreen(),
          '/asistente-supervisor': (context) => const AsistenteSupervisorScreen(),
          '/auditoria-prl': (context) => const AuditoriaPrlScreen(),
          '/solicitudes-ayuda': (context) => const SolicitudesAyudaScreen(),
          '/mi-actividad': (context) => const MiActividadScreen(),
          '/ast': (context) => const AstLoginScreen(),
        },
      ),
    );
  }
}

/// Resume + timer: verifica en panel si el dispositivo sigue habilitado.
class _TrazaboxSesionLifecycleGuard extends StatefulWidget {
  const _TrazaboxSesionLifecycleGuard({required this.child});

  final Widget child;

  @override
  State<_TrazaboxSesionLifecycleGuard> createState() =>
      _TrazaboxSesionLifecycleGuardState();
}

class _TrazaboxSesionLifecycleGuardState extends State<_TrazaboxSesionLifecycleGuard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SesionDispositivoService.iniciarTimerPeriodico();
  }

  @override
  void dispose() {
    SesionDispositivoService.detenerTimerPeriodico();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SesionDispositivoService.verificarSiCorresponde();
      unawaited(FcmService.instance.onAppResumed());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Rol de navegación (bodeguero / supervisor / técnico) desde prefs TRAZABOX.
Future<String> _getRolUsuario() async {
  try {
    await SessionManager.init();
    return await SessionManager.getRol();
  } catch (e) {
    print('Error obteniendo rol: $e');
    return 'tecnico';
  }
}

/// Pantalla principal según [rol_usuario] — Future estable para no parpadear.
class _AppHomeByRol extends StatefulWidget {
  const _AppHomeByRol();

  @override
  State<_AppHomeByRol> createState() => _AppHomeByRolState();
}

class _AppHomeByRolState extends State<_AppHomeByRol> {
  late final Future<String> _rolFuture;

  @override
  void initState() {
    super.initState();
    _rolFuture = _getRolUsuario();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _rolFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0A1628),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF00D9FF)),
            ),
          );
        }

        final rol = snapshot.data ?? 'tecnico';

        if (rol == 'bodeguero') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(FcmService.instance.syncFcmTokenDispositivo());
            unawaited(FcmService.instance.initBodegaGuiaMonitor());
            unawaited(FcmService.instance.initBodegaTraspasoMonitor());
          });
          return const BodegueroMenuScreen();
        }
        if (rol == 'supervisor') {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            unawaited(FcmService.instance.syncFcmTokenDispositivo());
            unawaited(FcmService.instance.initSupervisorAyudaMonitor());
            final rut = await AyudaService.resolverRutSupervisorSesion();
            if (rut.isNotEmpty) {
              unawaited(AyudaService().iniciarMonitoreoGlobalSupervisor(rut));
            }
          });
          return const AsistenteSupervisorScreen(esRaiz: true);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(FcmService.instance.syncFcmTokenDispositivo());
          unawaited(FcmService.instance.initSolicitudMonitor());
        });
        return const HomeScreen();
      },
    );
  }
}

/// Wrapper que maneja la navegación según el estado de registro
class AppWrapper extends StatelessWidget {
  const AppWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isLoading) {
          return Scaffold(
            backgroundColor: const Color(0xFF0A1628),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00D9FF), Color(0xFF0099CC)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.engineering,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      color: Color(0xFF00D9FF),
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Verificando dispositivo...',
                    style: TextStyle(
                      color: Color(0xFF8FA8C8),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (auth.registroEstado == RegistroEstado.error) {
          return Scaffold(
            backgroundColor: const Color(0xFF0A1628),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Color(0xFFFF6B35),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Error de conexión',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      auth.error ?? 'No se pudo verificar el dispositivo',
                      style: const TextStyle(
                        color: Color(0xFF8FA8C8),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () => auth.reintentar(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00D9FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Sin registro → pantalla de registro por RUT
        if (auth.necesitaRegistro) {
          return const RegistroRutScreen();
        }

        // Registrado pero falta desbloquear sesión
        if (auth.isAuthenticated && auth.requiereDesbloqueoSesion) {
          return const DesbloqueoAppScreen();
        }

        if (auth.isAuthenticated) {
          return const _AppHomeByRol();
        }

        return const RegistroRutScreen();
      },
    );
  }
}
