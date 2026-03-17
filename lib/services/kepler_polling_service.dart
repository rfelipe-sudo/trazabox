import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import 'deteccion_caminata_service.dart';
import 'supabase_service.dart';

class KeplerPollingService {
  static final KeplerPollingService _instance = KeplerPollingService._internal();
  factory KeplerPollingService() => _instance;
  KeplerPollingService._internal();

  static const String _endpoint = 'https://kepler.sbip.cl/api/v1/toa/get_data_toa_other_enterprise';
  static const int _intervaloSegundos = 30;

  Timer? _timer;
  String? _rutTecnico;
  String? _otActualMonitoreando;
  final DeteccionCaminataService _deteccionService = DeteccionCaminataService();
  final SupabaseService _supabaseService = SupabaseService();

  Future<void> iniciar() async {
    final prefs = await SharedPreferences.getInstance();
    _rutTecnico = prefs.getString('rut_tecnico');

    if (_rutTecnico == null || _rutTecnico!.isEmpty) {
      print('⚠️ [KeplerPolling] No hay RUT guardado - No se inicia polling');
      return;
    }

    print('✅ [KeplerPolling] Iniciando polling para RUT: $_rutTecnico');

    // Primera consulta inmediata
    await _consultarOrdenes();

    // Luego cada 30 segundos
    _timer = Timer.periodic(const Duration(seconds: _intervaloSegundos), (_) {
      _consultarOrdenes();
    });
  }

  void detener() {
    _timer?.cancel();
    _timer = null;
    print('🛑 [KeplerPolling] Polling detenido');
  }

  Future<void> _consultarOrdenes() async {
    try {
      print('🔄 [KeplerPolling] Consultando órdenes...');

      final prefs = await SharedPreferences.getInstance();

      final response = await http.get(
        Uri.parse(_endpoint),
        headers: AppConstants.keplerHeaders,
      );

      if (response.statusCode != 200) {
        print('❌ [KeplerPolling] Error HTTP: ${response.statusCode}');
        return;
      }

      final rawBody = response.body;
      print('📡 [KeplerPolling] Respuesta raw (primeros 200 chars): ${rawBody.length > 200 ? rawBody.substring(0, 200) : rawBody}');

      final data = jsonDecode(rawBody);
      print('📡 [KeplerPolling] Tipo de data: ${data.runtimeType}');

      List<dynamic> ordenes;
      if (data is List) {
        ordenes = data;
      } else if (data is Map) {
        final dataField = data['data'];
        if (dataField is List) {
          ordenes = dataField;
        } else {
          print('⚠️ [KeplerPolling] data["data"] no es List: ${dataField.runtimeType}');
          ordenes = [];
        }
      } else {
        print('⚠️ [KeplerPolling] Formato desconocido: ${data.runtimeType}');
        ordenes = [];
      }


      // Normalizar RUT: quitar puntos y espacios (igual que asistente_cto_screen)
      String normRut(String r) => r.replaceAll('.', '').replaceAll(' ', '').toLowerCase();

      // Filtrar: cualquier campo de estado == "Iniciado" AND Rut_tecnico == mi_rut
      final ordenesIniciadas = ordenes.where((orden) {
        if (orden is! Map) return false;
        final rutOrden = normRut(orden['Rut_tecnico']?.toString() ?? '');
        final mismoRut = normRut(_rutTecnico ?? '') == rutOrden;

        // Revisar todos los posibles campos de estado
        final estado          = orden['Estado']?.toString() ?? '';
        final estadoOrden     = orden['Estado Orden']?.toString() ?? '';
        final estadoActividad = orden['Estado de la actividad']?.toString() ?? '';
        final activityStatus  = orden['Activity status']?.toString() ?? '';

        final estaIniciado = estado == 'Iniciado' ||
            estadoOrden == 'Iniciado' ||
            estadoActividad == 'Iniciada' ||
            estadoActividad == 'Iniciado' ||
            activityStatus.toLowerCase().contains('start') ||
            activityStatus.toLowerCase().contains('inici');

        if (mismoRut) {
          print('🔍 [KeplerPolling] Orden del técnico: Estado="$estado" EstadoOrden="$estadoOrden" EstadoActividad="$estadoActividad" estaIniciado=$estaIniciado');
        }

        return mismoRut && estaIniciado;
      }).toList();

      print('📋 [KeplerPolling] Órdenes iniciadas para $_rutTecnico: ${ordenesIniciadas.length}');

      if (ordenesIniciadas.isEmpty) {
        // Si no hay órdenes iniciadas y había una monitoreando, finalizar
        if (_otActualMonitoreando != null) {
          print('🏁 [KeplerPolling] Orden $_otActualMonitoreando ya no está iniciada - Finalizando monitoreo');
          _deteccionService.finalizarTrabajo();
          _otActualMonitoreando = null;
          await prefs.remove('trabajo_activo');
          print('🗑️ [KeplerPolling] trabajo_activo eliminado');
        }
        return;
      }

      // Tomar la primera orden iniciada
      final ordenActiva = ordenesIniciadas.first as Map<String, dynamic>;
      final ot = ordenActiva['Orden_de_Trabajo']?.toString() ?? '';

      // Si ya estamos monitoreando esta OT, no hacer nada
      if (_otActualMonitoreando == ot) {
        print('⏳ [KeplerPolling] Ya monitoreando OT: $ot');
        return;
      }

      // Nueva orden iniciada - Activar monitoreo
      print('🚀 [KeplerPolling] Nueva orden detectada: $ot - Activando monitoreo');

      final nombreTecnico = ordenActiva['Técnico']?.toString() ?? '';
      final direccion = ordenActiva['Dirección']?.toString() ?? '';
      final coordY = ordenActiva['Coord_Y'];
      final coordX = ordenActiva['Coord_X'];
      final latTrabajo = coordY is num ? coordY.toDouble() : double.tryParse(coordY?.toString() ?? '');
      final lngTrabajo = coordX is num ? coordX.toDouble() : double.tryParse(coordX?.toString() ?? '');
      // "Access ID" es el campo de Kepler que identifica la CTO en Nyquist
      final accessId = ordenActiva['Access ID']?.toString();

      _otActualMonitoreando = ot;

      // ═══════════════════════════════════════════════════════
      // GUARDAR trabajo_activo directo en SharedPreferences
      // desde el isolate principal (no depender del background service)
      // ═══════════════════════════════════════════════════════
      await prefs.setString('trabajo_activo', jsonEncode({
        'ot': ot,
        'tecnico_id': _rutTecnico ?? '',
        'nombre_tecnico': nombreTecnico,
        'direccion': direccion,
        'hora_inicio': DateTime.now().toIso8601String(),
        'lat_inicial': latTrabajo ?? 0.0,
        'lng_inicial': lngTrabajo ?? 0.0,
        'access_id': accessId,
        'pasos_inicial': 0,
        'pasos_actual': 0,
        'distancia_max_recorrida': 0,
        'tiempo_caminando_segundos': 0,
        'detecto_caminata': false,
        'actividades_detectadas': [],
      }));
      print('✅ [KeplerPolling] trabajo_activo guardado: OT=$ot access_id=$accessId');

      // ═══════════════════════════════════════════════════════
      // ASOCIAR RUT ↔ NOMBRE (para alertas CTO)
      // ═══════════════════════════════════════════════════════
      if (_rutTecnico != null && nombreTecnico.isNotEmpty) {
        // Extraer nombre limpio (sin prefijo de empresa)
        String nombreLimpio = nombreTecnico;
        if (nombreTecnico.contains('_')) {
          final partes = nombreTecnico.split('_');
          nombreLimpio = partes.last; // Último segmento es el nombre
        }

        await _supabaseService.actualizarNombreTecnico(
          rut: _rutTecnico!,
          nombre: nombreLimpio,
          nombreFull: nombreTecnico,
        );

        print('✅ [KeplerPolling] Asociado RUT $_rutTecnico con nombre: $nombreLimpio');
      }

      // Asegurarse de que el servicio esté corriendo antes de iniciar trabajo
      await _deteccionService.iniciarServicio();

      _deteccionService.iniciarTrabajo(
        ot: ot,
        tecnicoId: _rutTecnico ?? '',
        nombreTecnico: nombreTecnico,
        direccion: direccion,
        latTrabajo: latTrabajo,
        lngTrabajo: lngTrabajo,
        accessId: accessId,
      );
    } catch (e) {
      print('❌ [KeplerPolling] Error: $e');
    }
  }

  // Método para actualizar el RUT (cuando el técnico se registra)
  Future<void> actualizarRut(String rut) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rut_tecnico', rut);
    _rutTecnico = rut;
    print('✅ [KeplerPolling] RUT actualizado: $rut');

    // Reiniciar polling con nuevo RUT
    detener();
    await iniciar();
  }
}

