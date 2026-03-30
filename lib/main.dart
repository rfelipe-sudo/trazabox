import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart' as activity_recognition;

import 'package:trazabox/constants/app_colors.dart';
import 'package:trazabox/config/supabase_config.dart';
import 'package:trazabox/providers/auth_provider.dart';
import 'package:trazabox/providers/alertas_provider.dart';
import 'package:trazabox/services/local_notification_service.dart';
import 'package:trazabox/services/alerta_contexto_service.dart';
import 'package:trazabox/services/churn_service.dart';
import 'package:trazabox/services/ayuda_service.dart';
import 'package:trazabox/services/estado_supervisor_service.dart';
import 'package:trazabox/services/supabase_service.dart';
import 'package:trazabox/screens/splash_screen.dart';
import 'package:trazabox/screens/registro_screen.dart';
import 'package:trazabox/screens/desbloqueo_app_screen.dart';
import 'package:trazabox/screens/home_screen.dart';
import 'package:trazabox/screens/asistente_cto_screen.dart';
import 'package:trazabox/screens/asistente_crea_terreno_screen.dart';
// import 'package:trazabox/screens/mapa_calor_screen.dart'; // COMENTADO: tester_red_shared no disponible
import 'package:trazabox/screens/ayuda_terreno_screen.dart';
import 'package:trazabox/screens/speed_meter_screen.dart';
import 'package:trazabox/screens/fiber_microscope_screen.dart';
import 'package:trazabox/screens/supervisor/mi_equipo_screen.dart';
import 'package:trazabox/screens/bodeguero_menu_screen.dart';
import 'package:trazabox/services/deteccion_caminata_service.dart';
import 'package:trazabox/services/portico_detector_service.dart';
import 'package:trazabox/services/kepler_polling_service.dart';
import 'package:trazabox/services/notificacion_service.dart';
import 'package:trazabox/services/alarm_audio_service.dart';
import 'package:trazabox/services/notification_service.dart' as notification_service;
import 'package:trazabox/services/update_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Helper para acceder a Supabase desde cualquier lugar
final supabaseService = SupabaseService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Solo configuración síncrona mínima antes de mostrar UI
  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF050810),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  } catch (_) {}

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

  // Mostrar la app inmediatamente — la splash se encarga de la espera visual
  runApp(const AgenteDesconexionesApp());

  // Todo lo demás en background, no bloquea la UI
  _inicializarServiciosEnBackground();
}

/// Inicialización no crítica que corre mientras la splash se muestra
Future<void> _inicializarServiciosEnBackground() async {
  // Canal de alta prioridad para Ayuda en Terreno (sonido + vibración)
  try {
    final notifAyuda = notification_service.NotificationService();
    await notifAyuda.init();
  } catch (e) { print('⚠️ [Main] NotificationService Ayuda: $e'); }

  try {
    final notificacionService = NotificacionService();
    await notificacionService.inicializar();
  } catch (e) { print('⚠️ [Main] NotificacionService: $e'); }

  try { await _solicitarPermisos(); } catch (_) {}
  try { _iniciarActivityRecognition(); } catch (_) {}
  try { await _crearCanalNotificacionDeteccion(); } catch (_) {}

  try {
    final deteccionService = DeteccionCaminataService();
    await deteccionService.inicializar();
  } catch (_) {}

  try { _configurarListenerAlertasAutomaticas(); } catch (_) {}

  // KeplerPollingService DESACTIVADO en TrazaBox — no corresponde a esta app
  // try {
  //   final keplerPolling = KeplerPollingService();
  //   await keplerPolling.iniciar();
  // } catch (e) { print('⚠️ [Main] KeplerPolling: $e'); }

  LocalNotificationService? notificationService;
  try {
    notificationService = LocalNotificationService();
    await notificationService.initialize();
  } catch (_) {}

  try { await AlertaContextoService().initialize(); } catch (_) {}

  try {
    if (notificationService != null) {
      await notificationService.cancelAllNotifications().timeout(
        const Duration(seconds: 3), onTimeout: () {},
      );
    }
    final alarmAudio = AlarmAudioService();
    if (alarmAudio.estaReproduciendo) {
      await alarmAudio.detenerAlarma().timeout(const Duration(seconds: 2), onTimeout: () {});
    }
  } catch (_) {}

  try {
    final ayudaService = AyudaService();
    // cargarHistorial migrado a Supabase Realtime — se carga al abrir pantalla
  } catch (_) {}

  try {
    final prefs = await SharedPreferences.getInstance();
    final rol = prefs.getString('rol_usuario') ?? 'tecnico';
    if (rol == 'tecnico') {
      final porticoDetector = PorticoDetectorService();
      await porticoDetector.iniciar();
      print('✅ [Main] PorticoDetectorService iniciado');
    }
  } catch (e) { print('⚠️ [Main] PorticoDetector: $e'); }

  print('✅ [Main] Servicios en background inicializados');
}

/// Inicializar Activity Recognition en el main isolate
void _iniciarActivityRecognition() {
  try {
    final activityRecognition = activity_recognition.FlutterActivityRecognition.instance;

    activityRecognition.activityStream.listen((activity) {
      print('🏃 [Main] Actividad detectada: ${activity.type}');

      // Enviar al background service
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
    
    // Verificar si el permiso está otorgado
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

  // ─────────────────────────────────────────────────────────
  // ALERTA: No se bajó de la camioneta (5 min)
  // ─────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────
  // ALERTA: Fuera de rango (>200m)
  // ─────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────
  // ALERTA: En movimiento (>20 km/h)
  // ─────────────────────────────────────────────────────────
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

class AgenteDesconexionesApp extends StatefulWidget {
  const AgenteDesconexionesApp({super.key});

  @override
  State<AgenteDesconexionesApp> createState() => _AgenteDesconexionesAppState();
}

class _AgenteDesconexionesAppState extends State<AgenteDesconexionesApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      UpdateService.tryDeletePendingTrazaBoxApk();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => AlertasProvider()),
        ChangeNotifierProvider(create: (_) => ChurnService()),
        ChangeNotifierProvider(create: (_) => AyudaService()),
        ChangeNotifierProvider(create: (_) => EstadoSupervisorService()),
      ],
      child: MaterialApp(
        title: 'Agente de Desconexiones',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const SplashScreen(),
        routes: {
          '/home': (context) => const AppWrapper(),
          '/asistente-cto': (context) => const AsistenteCtoScreen(),
          '/asistente-crea-terreno': (context) => const AsistenteCreaTerrenoScreen(),
          // '/mapa-calor': (context) => const MapaCalorScreen(), // COMENTADO: tester_red_shared no disponible
          '/ayuda-terreno': (context) => const AyudaTerrenoScreen(),
          '/speed-meter': (context) => const SpeedMeterScreen(),
          '/microscope': (context) => const FiberMicroscopeScreen(),
          '/supervisor-equipo': (context) => const MiEquipoScreen(),
        },
      ),
    );
  }
}

/// Función helper para obtener rol desde SharedPreferences
Future<String> _getRolUsuario() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_rol') ??
        prefs.getString('rol_usuario') ??
        'tecnico';
  } catch (e) {
    print('Error obteniendo rol: $e');
    return 'tecnico';
  }
}

/// Wrapper que maneja la navegación según el estado de registro
class AppWrapper extends StatelessWidget {
  const AppWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        // Mostrar loading mientras se verifica registro
        if (auth.isLoading) {
          return Scaffold(
            backgroundColor: const Color(0xFF0A1628),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo animado
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
        
        // Error al verificar
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
        
        // Dispositivo no registrado -> Pantalla de registro
        if (auth.necesitaRegistro) {
          return const RegistroScreen();
        }

        // Dispositivo registrado pero falta validar contraseña en esta sesión
        if (auth.isAuthenticated && auth.requiereDesbloqueoSesion) {
          return const DesbloqueoAppScreen();
        }
        
        // Dispositivo registrado -> Navegar según rol
        if (auth.isAuthenticated) {
          return FutureBuilder<String>(
            future: _getRolUsuario(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  backgroundColor: Color(0xFF0A1628),
                  body: Center(child: CircularProgressIndicator(color: Color(0xFF00D9FF))),
                );
              }
              
              final rol = snapshot.data ?? 'tecnico';
              
              // Bodegueros van a BodegueroMenuScreen
              if (rol == 'bodeguero') {
                return const BodegueroMenuScreen();
              }

              // Supervisores, ITO y técnicos: inicio en Home (Mi Equipo desde el botón del home).
              return const HomeScreen();
            },
          );
        }
        
        // Fallback a registro
        return const RegistroScreen();
      },
    );
  }
}
