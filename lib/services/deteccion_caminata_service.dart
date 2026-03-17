import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart' as activity_recognition;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pedometer_2/pedometer_2.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trazabox/models/trabajo_activo.dart';
import 'alertas_cto_service.dart';

/// Servicio de detección de caminata en segundo plano
@pragma('vm:entry-point')
class DeteccionCaminataService {
  @pragma('vm:entry-point')
  static final DeteccionCaminataService _instance = DeteccionCaminataService._internal();
  
  @pragma('vm:entry-point')
  factory DeteccionCaminataService() => _instance;
  
  @pragma('vm:entry-point')
  DeteccionCaminataService._internal();

  // Constantes de validación - NO SE BAJÓ
  static const int PASOS_MINIMOS = 25; // ~15-20 metros caminando
  static const double DISTANCIA_MINIMA_METROS = 8.0; // Reducido de 15 a 8 metros
  static const int TIEMPO_MINIMO_CAMINANDO_SEGUNDOS = 30; // 30 segundos de WALKING detectado
  static const int TIEMPO_MONITOREO_MINUTOS = 1; // 1 minuto para pruebas (cambiar a 5 en producción)

  // Constantes de validación - FUERA DE RANGO Y EN MOVIMIENTO
  static const double RADIO_MAXIMO_METROS = 200.0;
  static const double VELOCIDAD_MAXIMA_KMH = 20.0;
  static const double VELOCIDAD_MAXIMA_MS = 5.56;

  final FlutterBackgroundService _service = FlutterBackgroundService();

  // ═══════════════════════════════════════════════════════════
  // INICIALIZACIÓN DEL SERVICIO EN SEGUNDO PLANO
  // ═══════════════════════════════════════════════════════════

  Future<void> inicializar() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false, // Solo iniciar manualmente para supervisores
        autoStartOnBoot: false, // Evitar reinicios inesperados
        isForegroundMode: true,
        notificationChannelId: 'deteccion_caminata',
        initialNotificationTitle: 'TrazaBox',
        initialNotificationContent: 'En segundo plano',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false, // No iniciar automáticamente
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );

    print('✅ [DeteccionCaminata] Servicio inicializado');
  }

  Future<void> iniciarServicio() async {
    final isRunning = await _service.isRunning();
    if (!isRunning) {
      await _service.startService();
      print('🚀 [DeteccionCaminata] Servicio iniciado');
      // Esperar un momento para que el servicio se inicialice
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  // ═══════════════════════════════════════════════════════════
  // LÓGICA PRINCIPAL DEL SERVICIO (CORRE EN SEGUNDO PLANO)
  // ═══════════════════════════════════════════════════════════

  @pragma('vm:entry-point')
  static Future<void> _onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();

    // Streams de sensores
    StreamSubscription? pedometerSubscription;
    Timer? gpsTimer;
    Timer? timerValidacion;

    // Estado actual
    TrabajoActivo? trabajoActual;
    DateTime? ultimaActividadCaminando;
    int segundosCaminando = 0;

    // Variables para alertas adicionales
    bool alertaFueraDeRangoEnviada = false;
    bool alertaEnMovimientoEnviada = false;
    double? latitudTrabajo;
    double? longitudTrabajo;

    // ─────────────────────────────────────────────────────────
    // ESCUCHAR COMANDOS DESDE LA APP
    // ─────────────────────────────────────────────────────────

    service.on('iniciarTrabajo').listen((event) async {
      if (event == null) return;

      debugPrint('📥 Trabajo recibido: ${event['ot']}');

      // Obtener posición GPS inicial
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
      } catch (e) {
        debugPrint('❌ Error obteniendo GPS inicial: $e');
        return;
      }

      // Obtener pasos actuales
      int pasosIniciales = prefs.getInt('pasos_actuales') ?? 0;

      trabajoActual = TrabajoActivo(
        ot: event['ot'] as String,
        tecnicoId: event['tecnico_id'] as String,
        nombreTecnico: event['nombre_tecnico'] as String,
        direccion: event['direccion'] as String,
        horaInicio: DateTime.now(),
        latInicial: position.latitude,
        lngInicial: position.longitude,
        accessId: event['access_id'] as String?,
        pasosInicial: pasosIniciales,
      );

      // Guardar coordenadas del trabajo (desde Kepler)
      latitudTrabajo = (event['lat_trabajo'] as num?)?.toDouble() ?? position.latitude;
      longitudTrabajo = (event['lng_trabajo'] as num?)?.toDouble() ?? position.longitude;

      // Resetear flags de alertas
      alertaFueraDeRangoEnviada = false;
      alertaEnMovimientoEnviada = false;
      segundosCaminando = 0;

      // Guardar en storage
      await prefs.setString('trabajo_activo', jsonEncode(trabajoActual!.toJson()));

      // Actualizar notificación
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: '🔧 Trabajo: ${event['ot']}',
          content: 'Monitoreando actividad (5 min)...',
        );
      }

      debugPrint('✅ Trabajo iniciado - GPS técnico: ${position.latitude}, ${position.longitude}');
      debugPrint('✅ Coordenadas trabajo: $latitudTrabajo, $longitudTrabajo');
      debugPrint('✅ Pasos iniciales: $pasosIniciales');
      debugPrint('⏰ Iniciando timer de 5 minutos');

      // ═══════════════════════════════════════════════════════
      // TIMER DE 5 MINUTOS - VALIDACIÓN AUTOMÁTICA
      // ═══════════════════════════════════════════════════════
      timerValidacion?.cancel();
      timerValidacion = Timer(const Duration(minutes: TIEMPO_MONITOREO_MINUTOS), () async {
        debugPrint('⏰ Timer de 5 minutos completado - Validando automáticamente...');

        if (trabajoActual == null) return;

        // Actualizar pasos actuales
        trabajoActual!.pasosActual = prefs.getInt('pasos_actuales') ?? trabajoActual!.pasosInicial;

        final validacion = _validarRequisitos(trabajoActual!, segundosCaminando);

        if (!validacion.aprobado) {
          // ❌ NO SE BAJÓ - ENVIAR ALERTA AUTOMÁTICA
          debugPrint('🚨 Técnico NO se bajó - Enviando alerta automática a Supabase');

          service.invoke('alertaAutomatica', {
            'ot': trabajoActual!.ot,
            'tecnico_id': trabajoActual!.tecnicoId,
            'nombre_tecnico': trabajoActual!.nombreTecnico,
            'pasos_realizados': validacion.pasosRealizados,
            'distancia_recorrida': validacion.distanciaRecorrida,
            'razones_fallo': validacion.razonesFallo,
            'latitud': trabajoActual!.latInicial,
            'longitud': trabajoActual!.lngInicial,
          });

          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: '⚠️ Alerta enviada',
              content: 'No se detectó actividad en ${trabajoActual!.ot}',
            );
          }
        } else {
          // ✅ SE BAJÓ - TODO OK
          debugPrint('✅ Técnico se bajó correctamente - Sin alerta');

          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: '✅ Actividad verificada',
              content: '${trabajoActual!.ot} - OK',
            );
          }
        }
      });
    });

    service.on('finalizarTrabajo').listen((event) async {
      debugPrint('🏁 Trabajo finalizado - Cancelando timer');
      timerValidacion?.cancel();
      trabajoActual = null;
      segundosCaminando = 0;
      latitudTrabajo = null;
      longitudTrabajo = null;
      alertaFueraDeRangoEnviada = false;
      alertaEnMovimientoEnviada = false;
      await prefs.remove('trabajo_activo');

      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'CREA Monitoreo',
          content: 'Sin trabajo activo',
        );
      }
    });

    service.on('validarSinMoradores').listen((event) async {
      if (trabajoActual == null) {
        service.invoke('validacionResultado', {
          'aprobado': false,
          'mensaje': 'No hay trabajo activo',
        });
        return;
      }

      final validacion = _validarRequisitos(trabajoActual!, segundosCaminando);

      // Enviar resultado a la app
      service.invoke('validacionResultado', {
        'aprobado': validacion.aprobado,
        'cumple_pasos': validacion.cumplePasos,
        'cumple_distancia': validacion.cumpleDistancia,
        'cumple_caminata': validacion.cumpleCaminata,
        'pasos_realizados': validacion.pasosRealizados,
        'distancia_recorrida': validacion.distanciaRecorrida,
        'mensaje': validacion.mensaje,
        'razones_fallo': validacion.razonesFallo,
        'trabajo': trabajoActual!.toJson(),
      });

      debugPrint('📊 Validación: ${validacion.aprobado ? "APROBADA" : "RECHAZADA"}');
    });

    service.on('obtenerEstado').listen((event) async {
      if (trabajoActual != null) {
        service.invoke('estadoActual', {
          'tiene_trabajo': true,
          'trabajo': trabajoActual!.toJson(),
          'segundos_caminando': segundosCaminando,
        });
      } else {
        service.invoke('estadoActual', {
          'tiene_trabajo': false,
        });
      }
    });

    // ═══════════════════════════════════════════════════════
    // SENSOR 1: ACTIVITY RECOGNITION (recibido desde main isolate)
    // ═══════════════════════════════════════════════════════

    service.on('actividadDetectada').listen((event) {
      if (event == null) return;

      final tipo = event['tipo']?.toString() ?? '';
      print('🏃 [Background] Actividad recibida: $tipo');

      if (trabajoActual != null) {
        trabajoActual!.actividadesDetectadas.add(tipo);

        if (tipo.contains('WALKING') || 
            tipo.contains('ON_FOOT') ||
            tipo.contains('RUNNING')) {
          ultimaActividadCaminando = DateTime.now();
          trabajoActual!.detectoCaminata = true;
          print('✅ [Background] Caminata detectada!');
        }
      }
    });

    print('✅ [Background] Listener de Activity Recognition configurado');

    // ─────────────────────────────────────────────────────────
    // SENSOR 2: PODÓMETRO (CONTADOR DE PASOS)
    // ─────────────────────────────────────────────────────────

    try {
      final pedometer = Pedometer();
      // En pedometer_2 v5.x, stepCountStream es una función que devuelve un Stream<int>
      pedometerSubscription = pedometer.stepCountStream().listen((pasosActuales) {
        // En v5.x, el stream devuelve un int directamente
        prefs.setInt('pasos_actuales', pasosActuales);

        if (trabajoActual != null) {
          trabajoActual!.pasosActual = pasosActuales;
          final pasos = trabajoActual!.pasosRealizados;
          if (pasos % 10 == 0 && pasos > 0) {
            print('👟 [Background] Pasos: $pasos');
          }
        }
      });
      print('✅ [Background] Podómetro activo');
    } catch (e) {
      print('❌ [Background] Error Podómetro: $e');
    }

    // ─────────────────────────────────────────────────────────
    // SENSOR 3: GPS (DISTANCIA RECORRIDA)
    // ─────────────────────────────────────────────────────────

    gpsTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (trabajoActual == null) return;

      try {
        final posicionActual = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        // ─────────────────────────────────────────────────────
        // VALIDACIÓN 1: Distancia desde punto inicial (para pasos)
        // ─────────────────────────────────────────────────────
        final distanciaDesdeInicio = Geolocator.distanceBetween(
          trabajoActual!.latInicial,
          trabajoActual!.lngInicial,
          posicionActual.latitude,
          posicionActual.longitude,
        );

        if (distanciaDesdeInicio > trabajoActual!.distanciaMaxRecorrida) {
          trabajoActual!.distanciaMaxRecorrida = distanciaDesdeInicio;
        }

        // ─────────────────────────────────────────────────────
        // VALIDACIÓN 2: FUERA DE RANGO (>200m del punto de trabajo)
        // ─────────────────────────────────────────────────────
        if (latitudTrabajo != null && longitudTrabajo != null && !alertaFueraDeRangoEnviada) {
          final distanciaDesdeTrabajo = Geolocator.distanceBetween(
            latitudTrabajo!,
            longitudTrabajo!,
            posicionActual.latitude,
            posicionActual.longitude,
          );

          if (distanciaDesdeTrabajo > RADIO_MAXIMO_METROS) {
            debugPrint('🚨 [Background] ALERTA: Técnico FUERA DE RANGO - ${distanciaDesdeTrabajo.toStringAsFixed(0)}m');
            alertaFueraDeRangoEnviada = true;

            service.invoke('alertaFueraDeRango', {
              'tipo': 'fuera_de_rango',
              'ot': trabajoActual!.ot,
              'tecnico_id': trabajoActual!.tecnicoId,
              'nombre_tecnico': trabajoActual!.nombreTecnico,
              'distancia_desde_trabajo': distanciaDesdeTrabajo,
              'radio_maximo': RADIO_MAXIMO_METROS,
              'latitud_tecnico': posicionActual.latitude,
              'longitud_tecnico': posicionActual.longitude,
              'latitud_trabajo': latitudTrabajo,
              'longitud_trabajo': longitudTrabajo,
            });

            if (service is AndroidServiceInstance) {
              service.setForegroundNotificationInfo(
                title: '⚠️ Fuera de rango',
                content: '${trabajoActual!.ot} - ${distanciaDesdeTrabajo.toStringAsFixed(0)}m del punto',
              );
            }
          }
        }

        // ─────────────────────────────────────────────────────
        // VALIDACIÓN 3: EN MOVIMIENTO (>20 km/h)
        // ─────────────────────────────────────────────────────
        final velocidadMS = posicionActual.speed;
        final velocidadKMH = velocidadMS * 3.6;

        if (velocidadMS > VELOCIDAD_MAXIMA_MS && !alertaEnMovimientoEnviada) {
          debugPrint('🚨 [Background] ALERTA: Técnico EN MOVIMIENTO - ${velocidadKMH.toStringAsFixed(1)} km/h');
          alertaEnMovimientoEnviada = true;

          service.invoke('alertaEnMovimiento', {
            'tipo': 'en_movimiento',
            'ot': trabajoActual!.ot,
            'tecnico_id': trabajoActual!.tecnicoId,
            'nombre_tecnico': trabajoActual!.nombreTecnico,
            'velocidad_kmh': velocidadKMH,
            'velocidad_maxima': VELOCIDAD_MAXIMA_KMH,
            'latitud': posicionActual.latitude,
            'longitud': posicionActual.longitude,
          });

          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: '⚠️ En movimiento',
              content: '${trabajoActual!.ot} - ${velocidadKMH.toStringAsFixed(0)} km/h',
            );
          }
        }

        // Contar tiempo caminando
        if (ultimaActividadCaminando != null) {
          final diff = DateTime.now().difference(ultimaActividadCaminando!);
          if (diff.inSeconds < 15) {
            segundosCaminando += 10;
            trabajoActual!.tiempoCaminando = Duration(seconds: segundosCaminando);
          }
        }

        // Guardar estado
        await prefs.setString('trabajo_activo', jsonEncode(trabajoActual!.toJson()));

        // Actualizar notificación con progreso
        if (service is AndroidServiceInstance) {
          final minutosTranscurridos = DateTime.now().difference(trabajoActual!.horaInicio).inMinutes;
          if (minutosTranscurridos < TIEMPO_MONITOREO_MINUTOS) {
            final minutosRestantes = TIEMPO_MONITOREO_MINUTOS - minutosTranscurridos;
            service.setForegroundNotificationInfo(
              title: '🔧 ${trabajoActual!.ot}',
              content: '👟 ${trabajoActual!.pasosRealizados} pasos | 📍 ${distanciaDesdeInicio.toStringAsFixed(0)}m | ⏱️ ${minutosRestantes}min',
            );
          }
        }
      } catch (e) {
        debugPrint('❌ [Background] Error GPS: $e');
      }
    });

    // POLLING ALERTAS CTO DESACTIVADO en TrazaBox — no corresponde a esta app
    // Timer.periodic(const Duration(seconds: 60), (_) async {
    //   await AlertasCTOService.consultarDesdeBackground();
    // });

    // ─────────────────────────────────────────────────────────
    // MANTENER SERVICIO VIVO
    // ─────────────────────────────────────────────────────────

    service.on('stopService').listen((event) {
      pedometerSubscription?.cancel();
      gpsTimer?.cancel();
      timerValidacion?.cancel();
      service.stopSelf();
    });

    // ─────────────────────────────────────────────────────────
    // MONITOREO SUPERVISOR — alertas de solicitudes de ayuda
    // Activo cuando el usuario tiene rol supervisor/ito.
    // Corre en segundo plano incluso con la app minimizada.
    // ─────────────────────────────────────────────────────────
    _iniciarMonitoreoSupervisorEnBackground(service, prefs);
  }

  @pragma('vm:entry-point')
  static Future<void> _iniciarMonitoreoSupervisorEnBackground(
    ServiceInstance service,
    SharedPreferences prefs,
  ) async {
    final rol = prefs.getString('user_rol') ?? '';
    final rut = prefs.getString('rut_tecnico') ??
        prefs.getString('user_rut') ?? '';

    if ((rol != 'supervisor' && rol != 'ito') || rut.isEmpty) {
      debugPrint(
          '📡 [BG] No es supervisor/ITO — monitoreo ayuda omitido');
      return;
    }

    debugPrint('📡 [BG] Iniciando monitoreo supervisor $rut...');

    try {
      // Re-inicializar Supabase en este isolate
      // (cada isolate necesita su propia instancia)
      try {
        await Supabase.initialize(
          url: 'https://szoywhtkilgvfrczuyqn.supabase.co',
          anonKey:
              'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN6b3l3aHRraWxndmZyY3p1eXFuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyMjk3NTEsImV4cCI6MjA4NTgwNTc1MX0.sXoPmnZqRJXmaSfA0Mw9HlprVHI_okhTMKrSgONlAOk',
        );
      } catch (_) {
        // Ya inicializado en este isolate
      }

      final supabase = Supabase.instance.client;

      // Obtener equipo asignado a este supervisor
      List<String> rutsEquipo = [];
      try {
        final resp = await supabase
            .from('supervisor_tecnicos_traza')
            .select('rut_tecnico')
            .eq('rut_supervisor', rut);
        rutsEquipo = (resp as List)
            .map((e) => e['rut_tecnico'] as String)
            .toList();
        debugPrint(
            '📡 [BG] Equipo supervisor: ${rutsEquipo.length} técnicos');
      } catch (e) {
        debugPrint('⚠️ [BG] Error obteniendo equipo: $e');
      }

      // Inicializar sistema de notificaciones en este isolate
      final notifPlugin = FlutterLocalNotificationsPlugin();
      await notifPlugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      // Canal v4 (sin sonido custom = más fiable)
      await notifPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            AndroidNotificationChannel(
              'ayuda_terreno_v4',
              'Ayuda en Terreno',
              description: 'Alertas urgentes de solicitudes de ayuda',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
              vibrationPattern:
                  Int64List.fromList([0, 600, 200, 600, 200, 800]),
              enableLights: true,
            ),
          );

      // Actualizar notificación del foreground service
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'TrazaBox — Supervisor activo',
          content: 'Monitoreando solicitudes de tu equipo...',
        );
      }

      // IDs ya notificados (evitar duplicados entre Realtime y polling)
      final Set<String> notificados = {};

      void mostrarNotif(String nombreTec, String tipo, String ticketId) async {
        if (notificados.contains(ticketId)) return;
        notificados.add(ticketId);
        final vibracion = Int64List.fromList([0, 600, 200, 600, 200, 800]);
        await notifPlugin.show(
          3001,
          '🆘 Solicitud de $nombreTec',
          'Necesita ayuda: $tipo',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'ayuda_terreno_v4',
            'Ayuda en Terreno',
            channelDescription: 'Alertas urgentes de solicitudes de ayuda',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
              vibrationPattern: vibracion,
              fullScreenIntent: true,
              ticker: 'TrazaBox — Ayuda en Terreno',
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      }

      // 1. Realtime (principal)
      final bgChannel = supabase
          .channel('bg_ayuda_supervisor_$rut')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'ayuda_terreno',
            callback: (payload) async {
              final rec = payload.newRecord;
              final rutTec = rec['rut_tecnico'] ?? '';
              final nombreTec = rec['nombre_tecnico'] ?? 'Técnico';
              final tipo = rec['tipo'] ?? 'ayuda';
              final rutSupAsignado = rec['rut_supervisor'] ?? '';
              final ticketId = rec['ticket_id']?.toString() ?? '';

              final esMiEquipo = rutsEquipo.contains(rutTec) ||
                  rutSupAsignado == rut ||
                  (rutsEquipo.isEmpty && rutSupAsignado == null);
              if (!esMiEquipo) return;

              debugPrint('🔔 [BG] Realtime: $nombreTec ($tipo)');
              mostrarNotif(nombreTec, tipo, ticketId);
            },
          )
          .subscribe();

      // 2. Polling cada 45s como respaldo (por si Realtime se cae)
      Timer.periodic(const Duration(seconds: 45), (_) async {
        try {
          final desde = DateTime.now()
              .subtract(const Duration(hours: 2))
              .toIso8601String();
          final resp = await supabase
              .from('ayuda_terreno')
              .select('ticket_id, rut_tecnico, nombre_tecnico, tipo, rut_supervisor, created_at')
              .gte('created_at', desde)
              .eq('estado', 'pendiente')
              .order('created_at', ascending: false)
              .limit(20);

          for (final row in resp as List) {
            final rutTec = row['rut_tecnico'] ?? '';
            final nombreTec = row['nombre_tecnico'] ?? 'Técnico';
            final tipo = row['tipo'] ?? 'ayuda';
            final rutSupAsignado = row['rut_supervisor'] ?? '';
            final ticketId = row['ticket_id']?.toString() ?? '';

            final esMiEquipo = rutsEquipo.contains(rutTec) ||
                rutSupAsignado == rut ||
                (rutsEquipo.isEmpty && rutSupAsignado == null);
            if (!esMiEquipo) continue;

            mostrarNotif(nombreTec, tipo, ticketId);
          }
        } catch (e) {
          debugPrint('⚠️ [BG] Polling error: $e');
        }
      });

      debugPrint('✅ [BG] Supervisor $rut: Realtime + polling activos');
    } catch (e) {
      debugPrint(
          '❌ [BG] Error en monitoreo supervisor: $e');
    }
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    return true;
  }

  // ═══════════════════════════════════════════════════════════
  // VALIDACIÓN DE REQUISITOS PARA "SIN MORADORES"
  // ═══════════════════════════════════════════════════════════

  static ValidacionSinMoradores _validarRequisitos(
    TrabajoActivo trabajo,
    int segundosCaminando,
  ) {
    List<String> razonesFallo = [];

    // GPS - 8 metros mínimo
    final cumpleDistancia = trabajo.distanciaMaxRecorrida >= DISTANCIA_MINIMA_METROS;
    if (!cumpleDistancia) {
      razonesFallo.add('GPS: ${trabajo.distanciaMaxRecorrida.toStringAsFixed(1)}m (mínimo ${DISTANCIA_MINIMA_METROS}m)');
    }

    // Pasos - indicador secundario
    final cumplePasos = trabajo.pasosRealizados >= PASOS_MINIMOS;
    if (!cumplePasos) {
      razonesFallo.add('Pasos: ${trabajo.pasosRealizados}/$PASOS_MINIMOS');
    }

    // Activity Recognition - OBLIGATORIO (no se puede falsear agitando)
    final cumpleCaminata = trabajo.detectoCaminata && 
                           segundosCaminando >= TIEMPO_MINIMO_CAMINANDO_SEGUNDOS;
    if (!cumpleCaminata) {
      razonesFallo.add('Caminata real: ${segundosCaminando}s (mínimo ${TIEMPO_MINIMO_CAMINANDO_SEGUNDOS}s de WALKING)');
    }

    // NUEVA LÓGICA:
    // - Activity Recognition WALKING es OBLIGATORIO
    // - GPS o Pasos como respaldo
    final aprobado = cumpleCaminata && (cumpleDistancia || cumplePasos);

    // Detectar intento de fraude: pasos sin WALKING = agitando teléfono
    if (cumplePasos && !cumpleCaminata) {
      razonesFallo.add('⚠️ SOSPECHOSO: ${trabajo.pasosRealizados} pasos pero Activity NO detectó WALKING');
    }

    return ValidacionSinMoradores(
      aprobado: aprobado,
      cumplePasos: cumplePasos,
      cumpleDistancia: cumpleDistancia,
      cumpleCaminata: cumpleCaminata,
      pasosRealizados: trabajo.pasosRealizados,
      distanciaRecorrida: trabajo.distanciaMaxRecorrida,
      mensaje: aprobado 
          ? '✅ Técnico se bajó correctamente' 
          : '❌ Técnico no se bajó de la camioneta',
      razonesFallo: razonesFallo,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // MÉTODOS PÚBLICOS PARA USAR DESDE LA APP
  // ═══════════════════════════════════════════════════════════

  Future<void> iniciarTrabajo({
    required String ot,
    required String tecnicoId,
    required String nombreTecnico,
    required String direccion,
    double? latTrabajo,
    double? lngTrabajo,
    String? accessId,
  }) async {
    // Asegurarse de que el servicio esté corriendo
    final isRunning = await _service.isRunning();
    if (!isRunning) {
      await _service.startService();
      debugPrint('🚀 Servicio iniciado antes de comenzar trabajo');
      // Esperar un momento para que el servicio se inicialice
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    _service.invoke('iniciarTrabajo', {
      'ot': ot,
      'tecnico_id': tecnicoId,
      'nombre_tecnico': nombreTecnico,
      'direccion': direccion,
      'lat_trabajo': latTrabajo,
      'lng_trabajo': lngTrabajo,
      'access_id': accessId,
    });
    debugPrint('📤 Enviado comando iniciarTrabajo: $ot (access_id: $accessId)');
  }

  void finalizarTrabajo() {
    _service.invoke('finalizarTrabajo');
    debugPrint('📤 Enviado comando finalizarTrabajo');
  }

  void validarSinMoradores() {
    _service.invoke('validarSinMoradores');
    debugPrint('📤 Enviado comando validarSinMoradores');
  }

  Stream<Map<String, dynamic>?> get onValidacionResultado {
    return _service.on('validacionResultado');
  }

  Stream<Map<String, dynamic>?> get onEstadoActual {
    return _service.on('estadoActual');
  }

  void obtenerEstado() {
    _service.invoke('obtenerEstado');
  }

  /// Stream para escuchar alertas automáticas (cuando no se bajó después de 5 min)
  Stream<Map<String, dynamic>?> get onAlertaAutomatica {
    return _service.on('alertaAutomatica');
  }
}

