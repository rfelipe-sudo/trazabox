import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:trazabox/constants/app_colors.dart';
import 'package:trazabox/models/alerta.dart';
import 'package:trazabox/models/solicitud_ayuda.dart';
import 'package:trazabox/models/usuario.dart';
import 'package:trazabox/providers/auth_provider.dart';
import 'package:trazabox/providers/alertas_provider.dart';
import 'package:trazabox/screens/alerta_detail_screen.dart';
import 'package:trazabox/screens/registro_screen.dart';
import 'package:trazabox/screens/supervisor/alertas_fraude_screen.dart';
import 'package:trazabox/widgets/alerta_card.dart';
import 'package:trazabox/services/alarm_audio_service.dart';
import 'package:trazabox/services/deteccion_caminata_service.dart';
import 'package:trazabox/services/alertas_cto_service.dart';
import 'package:trazabox/screens/tu_mes_screen.dart';
import 'package:trazabox/screens/supervisor/mi_equipo_screen.dart';
import 'package:trazabox/screens/ayuda_terreno_screen.dart';
import 'package:trazabox/screens/supervisor/solicitudes_ayuda_screen.dart';
import 'package:trazabox/screens/supervisor/mi_actividad_screen.dart';
import 'package:trazabox/services/auth_service.dart';
import 'package:trazabox/services/ayuda_service.dart';
import 'package:trazabox/services/estado_supervisor_service.dart';
import 'package:trazabox/services/deteccion_caminata_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final _authService = AuthService();
  bool _puedeVerEquipo = false;
  bool _tieneAyudaPendiente = false;
  Future<List<Map<String, dynamic>>>? _historialAtencionFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Registrar observer para detectar cuando la app se cierra
    WidgetsBinding.instance.addObserver(this);
    
    // Activar wakelock para mantener pantalla encendida
    WakelockPlus.enable();
    
    // Verificar si puede ver equipo
    _checkPuedeVerEquipo();
    _checkAyudaPendiente();
    
    // AlertasCTOService DESACTIVADO — polling de desconexiones suspendido en TrazaBox
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // ═══════════════════════════════════════════════════════════
    // DETENER ALARMAS CUANDO LA APP SE CIERRA O VA A BACKGROUND
    // ═══════════════════════════════════════════════════════════
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      print('🔇 [HomeScreen] App en background/detenida - Deteniendo alarmas...');
      _detenerAlarmas();
    }

    // No re-iniciar en cada resume: puede causar loops y pérdida de conexión.
    // El canal global se inicia una vez en initState.
  }

  Future<void> _detenerAlarmas() async {
    try {
      final alarmAudio = AlarmAudioService();
      if (alarmAudio.estaReproduciendo) {
        await alarmAudio.detenerAlarma();
        print('✅ [HomeScreen] Alarma detenida');
      }
    } catch (e) {
      print('⚠️ [HomeScreen] Error deteniendo alarma: $e');
    }
  }

  @override
  void dispose() {
    // Desregistrar observer
    WidgetsBinding.instance.removeObserver(this);
    
    // Detener alarmas antes de cerrar
    _detenerAlarmas();
    
    // Desactivar wakelock al salir
    WakelockPlus.disable();
    _tabController.dispose();
    super.dispose();
  }

  void _navigateToAlerta(Alerta alerta) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlertaDetailScreen(alerta: alerta),
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro de que deseas cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.alertUrgent,
            ),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    
    if (confirmed == true && mounted) {
      // Detener monitoreo global de ayuda antes de cerrar sesión
      AyudaService().detenerMonitoreoGlobal();
      await context.read<AuthProvider>().logout();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RegistroScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final usuario = auth.usuario;
    
    if (usuario == null) {
      return const RegistroScreen();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      appBar: _buildAppBar(usuario),
      body: _puedeVerEquipo
          ? SingleChildScrollView(
              child: Column(
                children: [
                  _buildMiActividadCard(),
                  _buildActionButtons(),
                  _buildHistorialAtencion(),
                ],
              ),
            )
          : Column(
              children: [
                _buildActionButtons(),
                _buildTabBar(),
                Expanded(child: _buildAlertasList()),
              ],
            ),
    );
  }

  /// Probar el sistema de detección de fraude
  Future<void> _probarDeteccionFraude(BuildContext context) async {
    final deteccionService = DeteccionCaminataService();
    
    // Asegurarse de que el servicio esté corriendo
    await deteccionService.iniciarServicio();
    
    // Obtener ubicación actual para usar como punto de trabajo
    Position? posicionActual;
    try {
      posicionActual = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      print('📍 Ubicación actual: ${posicionActual.latitude}, ${posicionActual.longitude}');
    } catch (e) {
      print('❌ Error obteniendo ubicación: $e');
    }
    
    // Simular orden iniciada con ubicación actual
    deteccionService.iniciarTrabajo(
      ot: 'TEST-${DateTime.now().millisecondsSinceEpoch}',
      tecnicoId: 'TEC-001',
      nombreTecnico: 'Técnico Prueba',
      direccion: 'Ubicación actual de prueba',
      latTrabajo: posicionActual?.latitude,
      lngTrabajo: posicionActual?.longitude,
    );
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏱️ Monitoreo iniciado - 1 min para validar'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  PreferredSizeWidget _buildAppBar(Usuario usuario) {
    return AppBar(
      backgroundColor: const Color(0xFF0D1B2A),
      elevation: 0,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppColors.creaGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              usuario.esTecnico ? Icons.engineering : Icons.supervisor_account,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  usuario.nombre,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                Text(
                  usuario.rol.displayName,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8FA8C8),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Botón Tu Mes — solo activo para técnicos
        IconButton(
          icon: Icon(
            Icons.calendar_month,
            color: _puedeVerEquipo ? Colors.white38 : Colors.white,
          ),
          tooltip: _puedeVerEquipo ? 'Tu Mes (Próximamente)' : 'Tu Mes',
          onPressed: _puedeVerEquipo
              ? () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('📅 Tu Mes — Próximamente disponible para supervisores'),
                      backgroundColor: Color(0xFF1A2D50),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              : () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TuMesScreen(),
                    ),
                  );
                },
        ),
        // Botón de alertas de fraude solo para supervisores
        if (usuario.esSupervisor)
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.warning),
                tooltip: 'Alertas de Fraude',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AlertasFraudeScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            final alertas = context.read<AlertasProvider>();
            final auth = context.read<AuthProvider>();
            if (auth.usuario != null) {
              alertas.cargarAlertas(auth.usuario!);
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: _logout,
        ),
      ],
    );
  }

  Widget _buildMiActividadCard() {
    return Consumer<EstadoSupervisorService>(
      builder: (context, svc, _) {
        final estado = svc.estadoActual;
        final activo = estado?.estaActivo ?? false;
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MiActividadScreen()),
          ),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF1A2E42),
                  const Color(0xFF0D1B2A),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: activo ? const Color(0xFFFF9500).withOpacity(0.6) : Colors.white12,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (activo ? const Color(0xFFFF9500) : const Color(0xFF00E5FF)).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    activo ? Icons.pending_actions : Icons.check_circle_outline,
                    color: activo ? const Color(0xFFFF9500) : const Color(0xFF00E5FF),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MI ACTIVIDAD',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        activo
                            ? (estado?.nombreTecnicoActivo != null
                                ? '→ ${estado!.nombreTecnicoActivo}'
                                : 'Actividad en curso')
                            : 'Sin actividad',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 14),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButtons() {
    // Para supervisores: ocultar cards grises (próximamente), solo mostrar habilitadas
    final children = <Widget>[
      _buildActionButton(
        icon: Icons.router,
        label: 'Asistente\nde CTO',
        color: const Color(0xFF00D9FF),
        gradient: const LinearGradient(
          colors: [Color(0xFF00D9FF), Color(0xFF0099CC)],
        ),
        onTap: () {
          Navigator.of(context).pushNamed('/asistente-cto');
        },
      ),
      _buildActionButton(
        icon: Icons.mic,
        label: 'Asistente\nCREA',
        color: const Color(0xFFAB47BC),
        gradient: const LinearGradient(
          colors: [Color(0xFFAB47BC), Color(0xFF7B1FA2)],
        ),
        onTap: () {
          Navigator.of(context).pushNamed('/asistente-crea-terreno');
        },
      ),
      if (!_puedeVerEquipo)
        _buildActionButton(
          icon: Icons.map,
          label: 'Mapa de\nCalor',
          color: Colors.grey[600]!,
          gradient: LinearGradient(colors: [Colors.grey[700]!, Colors.grey[800]!]),
          onTap: () => _mostrarProntoDisponible(context),
          proximamente: true,
        ),
      _puedeVerEquipo
          ? _buildSolicitudesAyudaCard()
          : _buildAyudaTerrenoButton(),
      if (!_puedeVerEquipo)
        _buildActionButton(
          icon: Icons.speed,
          label: 'Medición\nde Velocidad',
          color: Colors.grey[600]!,
          gradient: LinearGradient(colors: [Colors.grey[700]!, Colors.grey[800]!]),
          onTap: () => _mostrarProntoDisponible(context),
          proximamente: true,
        ),
      if (!_puedeVerEquipo)
        _buildActionButton(
          icon: Icons.camera_enhance,
          label: 'Microscopio\nFibra',
          color: Colors.grey[600]!,
          gradient: LinearGradient(colors: [Colors.grey[700]!, Colors.grey[800]!]),
          onTap: () => _mostrarProntoDisponible(context),
          proximamente: true,
        ),
      if (_puedeVerEquipo)
        _buildActionButton(
          icon: Icons.groups,
          label: 'Mi Equipo',
          color: const Color(0xFFFFA500),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFA500), Color(0xFFFF8C00)],
          ),
          onTap: () {
            Navigator.of(context).pushNamed('/supervisor-equipo');
          },
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: children,
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1);
  }

  Future<void> _checkAyudaPendiente() async {
    final prefs = await SharedPreferences.getInstance();
    final ticket = prefs.getString('ayuda_ticket_activo');
    if (mounted) {
      setState(() => _tieneAyudaPendiente = ticket != null && ticket.isNotEmpty);
    }
  }

  Future<void> _checkPuedeVerEquipo() async {
    final puede = await _authService.puedeVerEquipo();
    if (mounted) {
      setState(() {
        _puedeVerEquipo = puede;
      });
    }
    if (puede) {
      final prefs = await SharedPreferences.getInstance();
      final rut = prefs.getString('rut_supervisor') ??
          prefs.getString('rut_tecnico') ??
          prefs.getString('user_rut');
      if (rut != null && rut.isNotEmpty) {
        final svc = EstadoSupervisorService();
        await svc.cargarEstado(rut);
        await svc.verificarRecoveryActividad(rut);
        svc.suscribirRealtime(rut);
        // Pre-cargar solicitudes para badge en card
        await AyudaService().cargarSolicitudesSupervisor(rut);
        if (mounted) setState(() {
          _historialAtencionFuture = AyudaService().obtenerHistorialAtencionDia(rut);
        });
      }
    }
    // Si es supervisor/ITO, iniciar canal global de monitoreo
    // para recibir alertas sonoras aunque la pantalla de solicitudes esté cerrada
    if (puede) {
      _iniciarMonitoreoGlobalSiSupervisor();
    }
  }

  Future<void> _iniciarMonitoreoGlobalSiSupervisor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rut = prefs.getString('rut_supervisor') ??
          prefs.getString('rut_tecnico') ??
          prefs.getString('user_rut') ?? '';
      if (rut.isEmpty) return;

      // Solicitar ignorar optimización de batería (ayuda a que el servicio
      // sobreviva cuando la app está cerrada o minimizada)
      try {
        final status = await Permission.ignoreBatteryOptimizations.status;
        if (!status.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();
        }
      } catch (_) {}

      // Canal en memoria (funciona con app abierta/minimizada en primer plano)
      final ayudaService = AyudaService();
      await ayudaService.iniciarMonitoreoGlobalSupervisor(rut);

      // Background service (persiste aunque el usuario cambie de app)
      try {
        final bgService = FlutterBackgroundService();
        final isRunning = await bgService.isRunning();
        if (!isRunning) {
          await DeteccionCaminataService().inicializar();
          await bgService.startService();
          debugPrint('🚀 [HomeScreen] Background service iniciado para supervisor');
        }
      } catch (e) {
        debugPrint('⚠️ [HomeScreen] BG service: $e');
      }
    } catch (e) {
      debugPrint('⚠️ [HomeScreen] Error iniciando monitoreo global: $e');
    }
  }

  Widget _buildSolicitudesAyudaCard() {
    return Consumer<AyudaService>(
      builder: (context, ayudaSvc, _) {
        final pendientes = ayudaSvc.solicitudesSupervisor
            .where((s) => s.estado == EstadoSolicitud.pendiente)
            .length;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            _buildActionButton(
              icon: Icons.headset_mic,
              label: 'Solicitudes\nde Ayuda',
              color: const Color(0xFFFF9500),
              gradient: const LinearGradient(
                colors: [Color(0xFFFF9500), Color(0xFFFF6B00)],
              ),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const SolicitudesAyudaScreen()),
                );
                if (mounted) {
                  final prefs = await SharedPreferences.getInstance();
                  final rut = prefs.getString('rut_supervisor') ??
                      prefs.getString('rut_tecnico') ??
                      prefs.getString('user_rut') ?? '';
                  if (rut.isNotEmpty && mounted) {
                    setState(() {
                      _historialAtencionFuture =
                          AyudaService().obtenerHistorialAtencionDia(rut);
                    });
                  }
                }
              },
            ),
            if (pendientes > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF3B30),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      pendientes > 9 ? '9+' : '$pendientes',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHistorialAtencion() {
    if (_historialAtencionFuture == null) return const SizedBox.shrink();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _historialAtencionFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final items = snapshot.data!;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1B2A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E3A5F)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Título estilo tab/alertas DX
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22).withOpacity(0.5),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        gradient: AppColors.creaGradient,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.history,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'HISTORIAL DE ATENCIÓN',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: items.take(5).map((item) {
                    final tipo = item['tipo'] as String? ?? 'ayuda';
                    final (tipoDisplay, colorTipo) = _historialTipoInfo(tipo);
                    final tiempoMin = item['tiempo_min'] as int? ?? 0;
                    final nombre = item['nombre_tecnico'] as String? ?? 'Técnico';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF151F2E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colorTipo.withOpacity(0.4),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: colorTipo.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              _historialIconoTipo(tipo),
                              color: colorTipo,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nombre,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorTipo.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        tipoDisplay,
                                        style: TextStyle(
                                          color: colorTipo,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${item['hora_desde'] ?? '—'} - ${item['hora_hasta'] ?? '—'}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '$tiempoMin min',
                                      style: TextStyle(
                                        color: colorTipo,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  (String, Color) _historialTipoInfo(String tipo) {
    return switch (tipo) {
      'zona_roja' => ('Zona Roja', const Color(0xFFFF3B30)),
      'cruce_peligroso' => ('Cruce Peligroso', const Color(0xFFFF9500)),
      'ducto' => ('Ducto', const Color(0xFFFFD60A)),
      'fusion' => ('Fusión', const Color(0xFF00E5FF)),
      'altura' => ('Altura', const Color(0xFF30D158)),
      _ => (tipo, const Color(0xFF00E5FF)),
    };
  }

  IconData _historialIconoTipo(String tipo) {
    return switch (tipo) {
      'zona_roja' => Icons.warning_amber,
      'cruce_peligroso' => Icons.traffic,
      'ducto' => Icons.block,
      'fusion' => Icons.cable,
      'altura' => Icons.height,
      _ => Icons.help_outline,
    };
  }

  Widget _buildAyudaTerrenoButton() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildActionButton(
          icon: Icons.support_agent,
          label: 'Ayuda en\nTerreno',
          color: const Color(0xFF30D158),
          gradient: const LinearGradient(
            colors: [Color(0xFF30D158), Color(0xFF1A9E3C)],
          ),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const AyudaTerrenoScreen()),
            );
            // Al volver, re-verificar si hay solicitud activa
            _checkAyudaPendiente();
          },
        ),
        if (_tieneAyudaPendiente)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: Color(0xFFFF3B30),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.circle, color: Colors.white, size: 8),
              ),
            ),
          ),
      ],
    );
  }

  void _mostrarProntoDisponible(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2C3D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction, size: 56, color: Color(0xFF00BCD4)),
            const SizedBox(height: 16),
            const Text(
              'ESTA HERRAMIENTA\nPRONTO ESTARÁ DISPONIBLE',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                height: 1.5,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: Color(0xFF00BCD4))),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required Gradient gradient,
    required VoidCallback onTap,
    bool proximamente = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 32, color: proximamente ? Colors.white38 : Colors.white),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: proximamente ? Colors.white38 : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (proximamente)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      'Próximo',
                      style: TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ).animate().scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E3A5F)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: AppColors.creaGradient,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF8FA8C8),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'Alertas Pendientes'),
          Tab(text: 'Historial de DX'),
        ],
      ),
    );
  }

  Widget _buildAlertasList() {
    return Consumer<AlertasProvider>(
      builder: (context, alertasProvider, _) {
        if (alertasProvider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00D9FF)),
          );
        }
        
        return TabBarView(
          controller: _tabController,
          children: [
            // Tab 1: Pendientes (todas las alertas que NO están resueltas)
            _buildListaAlertas(
              [
                ...alertasProvider.alertasPorEstado(EstadoAlerta.pendiente),
                ...alertasProvider.alertasPorEstado(EstadoAlerta.enAtencion),
                ...alertasProvider.alertasPorEstado(EstadoAlerta.postergada),
                ...alertasProvider.alertasPorEstado(EstadoAlerta.enRevisionCalidad),
                ...alertasProvider.alertasPorEstado(EstadoAlerta.escalada),
              ],
              emptyMessage: 'No hay alertas pendientes',
            ),
            
            // Tab 2: Historial (SOLO alertas resueltas: regularizada o cerrada)
            _buildListaAlertas(
              [
                ...alertasProvider.alertasPorEstado(EstadoAlerta.regularizada),
                ...alertasProvider.alertasPorEstado(EstadoAlerta.cerrada),
              ],
              emptyMessage: 'No hay historial de alertas',
            ),
          ],
        );
      },
    );
  }

  Widget _buildListaAlertas(List<Alerta> alertas, {required String emptyMessage}) {
    if (alertas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: const Color(0xFF5C7A99),
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: const TextStyle(
                color: Color(0xFF8FA8C8),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: () async {
        final auth = context.read<AuthProvider>();
        final alertasProvider = context.read<AlertasProvider>();
        if (auth.usuario != null) {
          await alertasProvider.cargarAlertas(auth.usuario!);
        }
      },
      color: const Color(0xFF00D9FF),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: alertas.length,
        itemBuilder: (context, index) {
          final alerta = alertas[index];
          return AlertaCard(
            alerta: alerta,
            onTap: () => _navigateToAlerta(alerta),
          ).animate(delay: (index * 100).ms).fadeIn().slideX(begin: 0.1);
        },
      ),
    );
  }
}
