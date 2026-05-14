import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:trazabox/constants/map_styles.dart';
import 'package:trazabox/models/solicitud_material.dart';
import 'package:trazabox/screens/entrega_en_camino_screen.dart';
import 'package:trazabox/screens/guia_entrega_screen.dart';
import 'package:trazabox/services/material_solicitud_service.dart';

class SolicitudMaterialScreen extends StatefulWidget {
  const SolicitudMaterialScreen({super.key});

  @override
  State<SolicitudMaterialScreen> createState() =>
      _SolicitudMaterialScreenState();
}

class _SolicitudMaterialScreenState extends State<SolicitudMaterialScreen> {
  static const Color _bg      = Color(0xFF0A1628);
  static const Color _surface = Color(0xFF0D1B2A);
  static const Color _accent  = Color(0xFF00D9FF);
  static const Color _border  = Color(0xFF1E3A5F);
  static const Color _textDim = Color(0xFF8FA8C8);
  static const Color _green   = Color(0xFF22C55E);
  static const Color _orange  = Color(0xFFF59E0B);
  static const Color _red     = Color(0xFFEF4444);

  // ── Identidad ────────────────────────────────────────────────
  String? _rut;
  String? _nombre;
  Position? _posicion;

  // ── Formulario ───────────────────────────────────────────────
  MaterialItem? _materialSeleccionado;
  int _cantidad = 1;

  // ── Estado solicitud propia ──────────────────────────────────
  SolicitudMaterial? _miSolicitud;
  bool _enviando = false;

  // ── Solicitudes cercanas (rol entregador) ────────────────────
  List<SolicitudMaterial> _cercanas = [];

  // ── Mapa ─────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  BitmapDescriptor? _iconoYo;
  BitmapDescriptor? _iconoTecnico;

  // ── Realtime ─────────────────────────────────────────────────
  StreamSubscription<List<Map<String, dynamic>>>? _subPropia;
  StreamSubscription<List<Map<String, dynamic>>>? _subDestinatarios;

  // ── Timer de 10 minutos ──────────────────────────────────────
  Timer? _timer10min;

  final _db      = Supabase.instance.client;
  final _service = MaterialSolicitudService();

  @override
  void initState() {
    super.initState();
    _crearIconos();
    _init();
  }

  @override
  void dispose() {
    _subPropia?.cancel();
    _subDestinatarios?.cancel();
    _timer10min?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // ── Iconos canvas para marcadores ────────────────────────────

  Future<void> _crearIconos() async {
    _iconoYo      = await _circleMarker(const Color(0xFF00D9FF), 72);
    _iconoTecnico = await _circleMarker(const Color(0xFF22C55E), 64);
    if (mounted) setState(() {});
  }

  Future<BitmapDescriptor> _circleMarker(Color color, double size) async {
    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);

    final shadow = Paint()
      ..color      = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(size / 2, size / 2 + 2), size / 2 - 4, shadow);

    final fill = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size / 2, size / 2), size / 2 - 6,
        [color, color.withValues(alpha: 0.75)],
      );
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 6, fill);
    canvas.drawCircle(
      Offset(size / 2, size / 2), size / 2 - 6,
      Paint()
        ..color       = Colors.white
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(Offset(size / 2, size / 2), size * 0.1,
        Paint()..color = Colors.white);

    final picture = recorder.endRecording();
    final image   = await picture.toImage(size.toInt(), size.toInt());
    final bytes   = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  // ── Init ─────────────────────────────────────────────────────

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _rut    = prefs.getString('rut_tecnico');
    _nombre = prefs.getString('nombre_tecnico') ?? 'Técnico';
    _posicion = await _obtenerPosicion();

    debugPrint('🔵 [SolicitudMat] init → rut=$_rut pos=${_posicion?.latitude},${_posicion?.longitude}');

    if (_rut == null) {
      debugPrint('🔴 [SolicitudMat] sin RUT, abortando init');
      return;
    }

    final rows = await _db
        .from('solicitudes_material')
        .select()
        .eq('rut_solicitante', _rut!)
        .inFilter('estado', ['pendiente', 'aceptada', 'en_guia'])
        .order('created_at', ascending: false)
        .limit(1);

    debugPrint('🔵 [SolicitudMat] solicitud propia activa: ${rows.length}');

    if (rows.isNotEmpty && mounted) {
      setState(() =>
          _miSolicitud = SolicitudMaterial.fromMap(rows.first as Map<String, dynamic>));
      _suscribirSolicitudPropia();
    }

    _suscribirCercanas();
    if (mounted) setState(() {});
  }

  Future<Position?> _obtenerPosicion() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return null;
      return Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));
    } catch (_) {
      return null;
    }
  }

  void _suscribirSolicitudPropia() {
    if (_miSolicitud == null) return;
    _subPropia?.cancel();
    _subPropia = _db
        .from('solicitudes_material')
        .stream(primaryKey: ['id'])
        .eq('id', _miSolicitud!.id)
        .listen((rows) {
      if (rows.isEmpty || !mounted) return;
      final updated =
          SolicitudMaterial.fromMap(rows.first as Map<String, dynamic>);
      setState(() => _miSolicitud = updated);

      if (updated.estado != 'pendiente') {
        _timer10min?.cancel();
      }
      if (updated.estado == 'en_guia' && updated.guiaId != null) {
        _abrirGuia(updated);
      }
    });
  }

  void _suscribirCercanas() {
    debugPrint('🔵 [SolicitudMat] suscribirCercanas → iniciando stream');
    _subDestinatarios?.cancel();
    _subDestinatarios = _db
        .from('solicitudes_material')
        .stream(primaryKey: ['id'])
        .eq('estado', 'pendiente')
        .listen((rows) {
      debugPrint('🟢 [SolicitudMat] stream cercanas disparado → ${rows.length} filas totales');
      if (!mounted) return;
      final todas = rows
          .map((r) => SolicitudMaterial.fromMap(r as Map<String, dynamic>))
          .where((s) => s.rutSolicitante != _rut)
          .toList();
      debugPrint('🟢 [SolicitudMat] de otros técnicos: ${todas.length}');
      final filtradas = todas.where((s) {
        if (_posicion == null ||
            s.latSolicitante == null ||
            s.lngSolicitante == null) {
          debugPrint('   ↳ sin GPS o sin coords → incluida por defecto: ${s.id}');
          return true;
        }
        final km = _distanciaKm(_posicion!.latitude, _posicion!.longitude,
            s.latSolicitante!, s.lngSolicitante!);
        debugPrint('   ↳ ${s.nombreSolicitante} @ ${km.toStringAsFixed(2)} km → ${km <= 5.0 ? "INCLUIDA" : "descartada"}');
        return km <= 5.0;
      }).toList();
      debugPrint('🟢 [SolicitudMat] cercanas finales: ${filtradas.length}');
      setState(() => _cercanas = filtradas);
      _actualizarMarkers();
    });
  }

  void _actualizarMarkers() {
    final markers = <Marker>{};

    // Mi posición
    final pos = _posicion;
    if (pos != null) {
      markers.add(Marker(
        markerId: const MarkerId('yo'),
        position: LatLng(pos.latitude, pos.longitude),
        icon: _iconoYo ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Mi posición'),
      ));
    }

    // Técnicos con solicitudes cercanas
    for (final s in _cercanas) {
      if (s.latSolicitante == null || s.lngSolicitante == null) continue;
      final dist = pos != null
          ? _distanciaKm(pos.latitude, pos.longitude,
                  s.latSolicitante!, s.lngSolicitante!)
              .toStringAsFixed(1)
          : '';
      markers.add(Marker(
        markerId: MarkerId(s.id),
        position: LatLng(s.latSolicitante!, s.lngSolicitante!),
        icon: _iconoTecnico ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: s.nombreSolicitante,
          snippet: '${s.tipoMaterial} ×${s.cantidad}  ${dist.isNotEmpty ? "$dist km" : ""}',
        ),
      ));
    }

    if (mounted) setState(() => _markers
      ..clear()
      ..addAll(markers));
  }

  double _distanciaKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _rad(double deg) => deg * math.pi / 180;

  // ── Enviar solicitud ─────────────────────────────────────────

  Future<void> _enviarSolicitud() async {
    if (_materialSeleccionado == null || _rut == null) return;

    debugPrint('🔵 [SolicitudMat] enviando solicitud: ${_materialSeleccionado!.nombre} ×$_cantidad pos=${_posicion?.latitude},${_posicion?.longitude}');
    setState(() => _enviando = true);
    try {
      final row = await _db.from('solicitudes_material').insert({
        'rut_solicitante':    _rut,
        'nombre_solicitante': _nombre,
        'lat_solicitante':    _posicion?.latitude,
        'lng_solicitante':    _posicion?.longitude,
        'tipo_material':      _materialSeleccionado!.nombre,
        'es_seriado':         _materialSeleccionado!.esSeriado,
        'cantidad':           _cantidad,
        'series':             [],
        'estado':             'pendiente',
      }).select().single();

      final sol = SolicitudMaterial.fromMap(row as Map<String, dynamic>);
      debugPrint('🟢 [SolicitudMat] solicitud creada id=${sol.id}');
      setState(() {
        _miSolicitud = sol;
        _enviando    = false;
      });
      _suscribirSolicitudPropia();
      _actualizarMarkers();

      // Notificar técnicos cercanos con stock (background)
      debugPrint('🔵 [SolicitudMat] lanzando notificarDestinatarios en background...');
      _service.notificarDestinatarios(
        solicitudId:    sol.id,
        tipoMaterial:   sol.tipoMaterial,
        latSolicitante: sol.latSolicitante,
        lngSolicitante: sol.lngSolicitante,
        rutSolicitante: _rut!,
      );

      // Alerta de 10 minutos si nadie responde
      _timer10min?.cancel();
      _timer10min = Timer(const Duration(minutes: 10), () {
        _mostrarAlertaSinRespuesta(sol);
      });
    } catch (e) {
      debugPrint('🔴 [SolicitudMat] error al enviar: $e');
      setState(() => _enviando = false);
      _snack('Error al enviar: $e');
    }
  }

  Future<void> _mostrarAlertaSinRespuesta(SolicitudMaterial sol) async {
    if (!mounted || _miSolicitud?.estado != 'pendiente') return;

    final pendientes =
        await _service.destinatariosPendientes(sol.id);
    if (!mounted) return;

    if (pendientes.isEmpty) {
      _snack('Nadie tiene stock cercano — sin respuesta en 10 min');
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: _border)),
        title: Row(children: [
          Icon(Icons.timer_off_outlined, color: _orange, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Sin respuesta (10 min)',
                style:
                    TextStyle(color: Colors.white, fontSize: 15)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Técnicos notificados que aún no responden:',
                style:
                    TextStyle(color: _textDim, fontSize: 12)),
            const SizedBox(height: 10),
            ...pendientes.map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: _orange,
                          shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        d['nombre_tecnico'] as String? ?? '',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${d['stock_disponible']} u.',
                        style: TextStyle(
                            color: _green, fontSize: 11),
                      ),
                    ),
                  ]),
                )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido',
                style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
  }

  // ── Aceptar solicitud (rol entregador) ───────────────────────

  Future<void> _aceptarSolicitud(SolicitudMaterial sol) async {
    if (_rut == null) return;
    try {
      await _service.aceptar(
        solicitudId:     sol.id,
        rutAceptador:    _rut!,
        nombreAceptador: _nombre ?? '',
        lat:             _posicion?.latitude,
        lng:             _posicion?.longitude,
      );

      final updated = SolicitudMaterial.fromMap(
        (await _db
                .from('solicitudes_material')
                .select()
                .eq('id', sol.id)
                .single())
            as Map<String, dynamic>,
      );
      if (mounted) {
        Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => EntregaEnCaminoScreen(
              solicitud:        updated,
              rutPropio:        _rut!,
              nombrePropio:     _nombre ?? '',
              posicionInicial:  _posicion,
            ),
          ),
        );
      }
    } catch (e) {
      _snack('Error al aceptar: $e');
    }
  }

  void _abrirGuia(SolicitudMaterial sol) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => GuiaEntregaScreen(
          solicitud:    sol,
          esEntregador: false,
          rutPropio:    _rut!,
          nombrePropio: _nombre ?? '',
          posicion:     _posicion,
        ),
      ),
    );
  }

  Future<void> _cancelar() async {
    if (_miSolicitud == null) return;
    _timer10min?.cancel();
    await _db
        .from('solicitudes_material')
        .update({'estado': 'cancelada'}).eq('id', _miSolicitud!.id);
    _subPropia?.cancel();
    setState(() => _miSolicitud = null);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Si hay solicitud pendiente → vista de mapa full-body
    if (_miSolicitud != null && _miSolicitud!.estado == 'pendiente') {
      return _buildMapaView();
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Solicitud de Material',
            style: TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Solicitudes cercanas (rol entregador) ──
          if (_cercanas.isNotEmpty) ...[
            _seccion('SOLICITUDES CERCANAS', Icons.people_alt_outlined, _accent),
            const SizedBox(height: 8),
            ..._cercanas.map(_buildSolicitudCercana),
            const SizedBox(height: 20),
          ],

          // ── Mi solicitud activa (aceptada / en_guia) ──
          if (_miSolicitud != null) ...[
            _seccion('MI SOLICITUD', Icons.inventory_2_outlined, _orange),
            const SizedBox(height: 8),
            _buildMiSolicitudCard(),
          ] else ...[
            // ── Formulario ──
            _seccion('NUEVA SOLICITUD', Icons.add_box_outlined, _accent),
            const SizedBox(height: 12),
            _buildFormulario(),
          ],
        ],
      ),
    );
  }

  // ── Vista mapa (estado pendiente) ────────────────────────────

  Widget _buildMapaView() {
    final sol = _miSolicitud!;
    final pos = _posicion;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // ── Mapa full-screen ──────────────────────────────────
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: pos != null
                    ? LatLng(pos.latitude, pos.longitude)
                    : const LatLng(-33.45, -70.66),
                zoom: 14,
              ),
              markers:               _markers,
              myLocationEnabled:     false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled:   false,
              mapToolbarEnabled:     false,
              compassEnabled:        false,
              mapType:               MapType.normal,
              style:                 MapStyles.estiloMapaUberDark,
              onMapCreated: (ctrl) {
                _mapController = ctrl;
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) _actualizarMarkers();
                });
              },
            ),
          ),

          // ── Banner superior ───────────────────────────────────
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(
                    children: [
                      // Botón volver
                      GestureDetector(
                        onTap: () => Navigator.maybePop(context),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 8)
                            ],
                          ),
                          child: const Icon(Icons.arrow_back,
                              color: Colors.black87, size: 20),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Chip de estado
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _orange.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                                color: _orange.withValues(alpha: 0.3),
                                blurRadius: 8)
                          ],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(
                            width: 8,
                            height: 8,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('Buscando…',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ]),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Barra de búsqueda animada
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 10,
                            spreadRadius: 2)
                      ],
                    ),
                    child: Row(
                      children: [
                        // Icono en movimiento
                        const Icon(Icons.directions_walk,
                                color: Color(0xFF00D9FF), size: 22)
                            .animate(onPlay: (c) => c.repeat())
                            .shimmer(
                                duration: 1400.ms,
                                color: Colors.white.withValues(alpha: 0.7))
                            .then()
                            .shake(hz: 2, duration: 600.ms),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Revisando stock de materiales\nen móviles cercanos…',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                                height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Panel inferior ────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, -4))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(sol.tipoMaterial,
                            style: const TextStyle(
                                color: _orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ),
                      const SizedBox(width: 8),
                      Text('× ${sol.cantidad}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      if (sol.esSeriado) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4)),
                          child: const Text('SERIADO',
                              style:
                                  TextStyle(color: _accent, fontSize: 9)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      'Las series se registran en la guía de entrega',
                      style: TextStyle(
                          color: _textDim.withValues(alpha: 0.7), fontSize: 11),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _cancelar,
                        style: OutlinedButton.styleFrom(
                            foregroundColor: _red,
                            side: BorderSide(
                                color: _red.withValues(alpha: 0.5)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 12)),
                        child: const Text('Cancelar solicitud'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Pulse de radar ────────────────────────────────────
          if (pos != null)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.38,
              left: MediaQuery.of(context).size.width / 2 - 50,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: _accent.withValues(alpha: 0.4), width: 2),
                ),
              )
                  .animate(onPlay: (c) => c.repeat())
                  .scale(
                      begin: const Offset(1, 1),
                      end: const Offset(2.5, 2.5),
                      duration: 2000.ms,
                      curve: Curves.easeOut)
                  .fadeOut(duration: 1500.ms),
            ),
        ],
      ),
    );
  }

  // ── Encabezado de sección ────────────────────────────────────

  Widget _seccion(String titulo, IconData icon, Color color) => Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(titulo,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.8)),
        ],
      );

  // ── Card solicitud cercana (rol entregador) ──────────────────

  Widget _buildSolicitudCercana(SolicitudMaterial sol) {
    final dist = (_posicion != null &&
            sol.latSolicitante != null &&
            sol.lngSolicitante != null)
        ? _distanciaKm(_posicion!.latitude, _posicion!.longitude,
                sol.latSolicitante!, sol.lngSolicitante!)
            .toStringAsFixed(1)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _orange.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6)),
            child: Text(sol.tipoMaterial,
                style: const TextStyle(
                    color: _orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Text('× ${sol.cantidad}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          if (sol.esSeriado) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4)),
              child: const Text('SERIADO',
                  style: TextStyle(color: _accent, fontSize: 9)),
            ),
          ],
          const Spacer(),
          if (dist != null)
            Text('$dist km',
                style: const TextStyle(color: _textDim, fontSize: 11)),
        ]),
        const SizedBox(height: 6),
        Text(sol.nombreSolicitante,
            style: const TextStyle(color: _textDim, fontSize: 12)),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => _aceptarSolicitud(sol),
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Aceptar y entregar',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ),
      ]),
    );
  }

  // ── Card solicitud propia (aceptada / en_guia) ───────────────

  Widget _buildMiSolicitudCard() {
    final sol = _miSolicitud!;
    final (label, color, icon) = switch (sol.estado) {
      'aceptada' => (
          'Técnico en camino: ${sol.nombreEntregador}',
          _green,
          Icons.directions_walk
        ),
      'en_guia' => (
          'Listo para firmar guía',
          _accent,
          Icons.draw_outlined
        ),
      _ => ('Estado: ${sol.estado}', _textDim, Icons.info_outline),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ),
        ]),
        const SizedBox(height: 12),
        _fila('Material', sol.tipoMaterial),
        _fila('Cantidad', '${sol.cantidad}'),
        const SizedBox(height: 12),
        if (sol.estado == 'en_guia')
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _abrirGuia(sol),
              icon: const Icon(Icons.draw_outlined, size: 16),
              label: const Text('Firmar guía'),
              style: FilledButton.styleFrom(backgroundColor: _accent),
            ),
          ),
      ]),
    );
  }

  Widget _fila(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Text('$label: ',
              style: const TextStyle(color: _textDim, fontSize: 12)),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ]),
      );

  // ── Formulario nueva solicitud ───────────────────────────────

  Widget _buildFormulario() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Material selector
      Container(
        decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border)),
        child: Column(
          children: [
            _grupoMaterial('No seriados',
                kMateriales.where((m) => !m.esSeriado).toList()),
            const Divider(height: 1, color: Color(0xFF1E3A5F)),
            _grupoMaterial('Seriados',
                kMateriales.where((m) => m.esSeriado).toList()),
          ],
        ),
      ),

      const SizedBox(height: 16),

      if (_materialSeleccionado != null) ...[
        // Cantidad
        const Text('Cantidad',
            style: TextStyle(color: _textDim, fontSize: 12)),
        const SizedBox(height: 6),
        Row(children: [
          _btnCantidad(Icons.remove, () {
            if (_cantidad > 1) setState(() => _cantidad--);
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('$_cantidad',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20)),
          ),
          _btnCantidad(Icons.add, () => setState(() => _cantidad++)),
        ]),

        if (_materialSeleccionado!.esSeriado) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _accent.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, color: _accent, size: 14),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Las series se registran al generar la guía de entrega.',
                  style: TextStyle(color: _accent, fontSize: 11),
                ),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 16),

        // Botón enviar
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _enviando ? null : _enviarSolicitud,
            icon: _enviando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send, size: 18),
            label: Text(_enviando ? 'Enviando...' : 'Enviar solicitud',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ] else
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border)),
          child: const Row(children: [
            Icon(Icons.touch_app, color: _textDim, size: 18),
            SizedBox(width: 10),
            Text('Selecciona un material de la lista',
                style: TextStyle(color: _textDim, fontSize: 13)),
          ]),
        ),
    ]);
  }

  Widget _grupoMaterial(String titulo, List<MaterialItem> items) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Text(titulo.toUpperCase(),
            style: const TextStyle(
                color: _textDim,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8)),
      ),
      ...items.map((m) {
        final sel = _materialSeleccionado?.nombre == m.nombre;
        return InkWell(
          onTap: () => setState(() {
            _materialSeleccionado = m;
            _cantidad = 1;
          }),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: sel ? _accent.withValues(alpha: 0.1) : Colors.transparent,
              border: Border(
                  left: BorderSide(
                      color: sel ? _accent : Colors.transparent,
                      width: 3)),
            ),
            child: Row(children: [
              Icon(
                m.esSeriado
                    ? Icons.memory_outlined
                    : Icons.cable_outlined,
                color: sel ? _accent : _textDim,
                size: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(m.nombre,
                    style: TextStyle(
                        color: sel ? Colors.white : _textDim,
                        fontSize: 13,
                        fontWeight:
                            sel ? FontWeight.bold : FontWeight.normal)),
              ),
              if (sel)
                const Icon(Icons.check_circle, color: _accent, size: 16),
            ]),
          ),
        );
      }),
    ]);
  }

  Widget _btnCantidad(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border)),
          child: Icon(icon, color: _accent, size: 20),
        ),
      );
}
