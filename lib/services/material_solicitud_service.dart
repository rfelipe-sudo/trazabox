import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:trazabox/config/constants.dart';
import 'package:trazabox/services/logistica_service.dart';

class ResultadoNotificacionDestinatarios {
  const ResultadoNotificacionDestinatarios({
    required this.cantidad,
    this.keplerDisponible = true,
  });

  final int cantidad;
  final bool keplerDisponible;

  bool get sinDestinatarios => cantidad == 0;
}

class MaterialSolicitudService {
  final _db = Supabase.instance.client;

  static const _fcmTimeout = Duration(seconds: 8);

  (double, double)? _buscarUbicacion(
    String rut,
    Map<String, (double, double)> ubicMap,
  ) {
    for (final entry in ubicMap.entries) {
      if (LogisticaService.sameRut(entry.key, rut)) return entry.value;
    }
    return null;
  }

  Future<void> _enviarFcmMaterial({
    required List<String> ruts,
    required String solicitudId,
    required String tipoMaterial,
  }) async {
    if (ruts.isEmpty) return;
    try {
      final tokenRows = await _db
          .from('tecnicos_traza_zc')
          .select('rut, fcm_token')
          .inFilter('rut', ruts);
      final tokens = <String>[];
      for (final row in tokenRows as List) {
        final token = row['fcm_token']?.toString() ?? '';
        if (token.isNotEmpty) tokens.add(token);
      }
      if (tokens.isEmpty) return;
      await _db.functions.invoke('fcm-send', body: {
        if (tokens.length == 1) 'token': tokens.first else 'tokens': tokens,
        'accion': 'solicitud_material',
        'title': '¡Solicitud de material!',
        'tipo': '¡Solicitud de material!',
        'body': 'Se necesita: $tipoMaterial',
        'descripcion': 'Se necesita: $tipoMaterial',
        'solicitud_id': solicitudId,
        'data_only': true,
        'skip_notification': true,
        'android_channel_id': 'mat_alertas_7',
        'android_priority': 'high',
      }).timeout(_fcmTimeout);
      debugPrint('✅ [Material] FCM → ${tokens.length} dispositivo(s)');
    } catch (e) {
      debugPrint('⚠️ [Material] FCM falló: $e');
    }
  }

  static bool _ubicacionVigente(String? updatedAt) {
    if (updatedAt == null || updatedAt.isEmpty) return false;
    try {
      final t = DateTime.parse(updatedAt).toUtc();
      final maxAntiguedad = Duration(
        minutes: kMaterialGpsMaxAntiguedadMinutos,
      );
      return DateTime.now().toUtc().difference(t) <= maxAntiguedad;
    } catch (_) {
      return false;
    }
  }

  /// Encuentra técnicos con stock suficiente y los notifica.
  Future<ResultadoNotificacionDestinatarios> notificarDestinatarios({
    required String solicitudId,
    required String tipoMaterial,
    required double? latSolicitante,
    required double? lngSolicitante,
    required String rutSolicitante,
    bool soloRadio5Km = true,
  }) async {
    List<TecnicoStock> stock;
    var keplerDisponible = true;
    try {
      stock = await LogisticaService().fetchStock();
    } catch (e) {
      keplerDisponible = false;
      debugPrint('⚠️ [Material] Kepler no disponible: $e');
      return const ResultadoNotificacionDestinatarios(
        cantidad: 0,
        keplerDisponible: false,
      );
    }

    List<dynamic> ubicRows;
    try {
      ubicRows = await _db
          .from('tecnicos_ubicacion')
          .select('tecnico_id, latitud, longitud, en_linea, ultima_actualizacion');
    } catch (e) {
      debugPrint('⚠️ [Material] error ubicaciones: $e');
      return ResultadoNotificacionDestinatarios(
        cantidad: 0,
        keplerDisponible: keplerDisponible,
      );
    }

    final Map<String, (double, double)> ubicMap = {};
    for (final u in ubicRows) {
      final rut = u['tecnico_id'] as String?;
      if (rut == null || rut.isEmpty) continue;
      if (u['en_linea'] != true) continue;
      if (!_ubicacionVigente(u['ultima_actualizacion'] as String?)) continue;
      final lat = (u['latitud'] as num?)?.toDouble();
      final lng = (u['longitud'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      if (lat.abs() < 0.0001 && lng.abs() < 0.0001) continue;
      ubicMap[rut] = (lat, lng);
    }

    final esExtensor = tipoMaterial.contains('Extensor');
    final umbralStock = esExtensor ? 3.0 : 5.0;
    final aplicarRadio =
        soloRadio5Km && kMaterialFiltroDistanciaActivo;

    final candidatos = <({TecnicoStock tecnico, double dist})>[];

    for (final tecnico in stock) {
      if (LogisticaService.normalizeRutKey(tecnico.rut) ==
          LogisticaService.normalizeRutKey(rutSolicitante)) {
        continue;
      }

      final cantidad = tecnico.stock[tipoMaterial] ?? 0;
      if (cantidad <= umbralStock) continue;

      final pos = _buscarUbicacion(tecnico.rut, ubicMap);
      if (pos == null) continue;

      double dist = 0;
      if (latSolicitante != null && lngSolicitante != null) {
        dist = _distanciaKm(
          latSolicitante,
          lngSolicitante,
          pos.$1,
          pos.$2,
        );
        if (aplicarRadio && dist > kMaterialRadioKm) continue;
      }

      candidatos.add((tecnico: tecnico, dist: dist));
    }

    candidatos.sort((a, b) => a.dist.compareTo(b.dist));

    final destinatarios = candidatos
        .map((c) => {
              'solicitud_id': solicitudId,
              'rut_tecnico': c.tecnico.rut,
              'nombre_tecnico': c.tecnico.nombre,
              'stock_disponible': (c.tecnico.stock[tipoMaterial] ?? 0).toInt(),
              'estado': 'pendiente',
            })
        .toList();

    if (destinatarios.isEmpty) {
      return ResultadoNotificacionDestinatarios(
        cantidad: 0,
        keplerDisponible: keplerDisponible,
      );
    }

    await _db.from('solicitudes_material_destinatarios').insert(destinatarios);

    await _enviarFcmMaterial(
      ruts: destinatarios
          .map((d) => d['rut_tecnico'] as String)
          .toList(),
      solicitudId: solicitudId,
      tipoMaterial: tipoMaterial,
    );

    for (final d in destinatarios) {
      try {
        await _db.from('alertas_fcm').upsert({
          'rut_tecnico': d['rut_tecnico'],
          'activa': true,
          'tipo': 'solicitud_material',
          'descripcion': 'Solicitud de material: $tipoMaterial',
        }, onConflict: 'rut_tecnico');
      } catch (_) {}
    }

    return ResultadoNotificacionDestinatarios(
      cantidad: destinatarios.length,
      keplerDisponible: keplerDisponible,
    );
  }

  /// El primer técnico que acepta: cancela los otros destinatarios y actualiza la solicitud.
  Future<void> aceptar({
    required String solicitudId,
    required String rutAceptador,
    required String nombreAceptador,
    required double? lat,
    required double? lng,
  }) async {
    await _db
        .from('solicitudes_material_destinatarios')
        .update({'estado': 'aceptada'})
        .eq('solicitud_id', solicitudId)
        .eq('rut_tecnico', rutAceptador);

    await _db
        .from('solicitudes_material_destinatarios')
        .update({'estado': 'cancelada'})
        .eq('solicitud_id', solicitudId)
        .neq('rut_tecnico', rutAceptador)
        .eq('estado', 'pendiente');

    await _db.from('solicitudes_material').update({
      'estado': 'aceptada',
      'rut_entregador': rutAceptador,
      'nombre_entregador': nombreAceptador,
      'lat_entregador': lat,
      'lng_entregador': lng,
    }).eq('id', solicitudId).eq('estado', 'pendiente');
  }

  Future<List<Map<String, dynamic>>> destinatariosPendientes(
    String solicitudId,
  ) async {
    final rows = await _db
        .from('solicitudes_material_destinatarios')
        .select()
        .eq('solicitud_id', solicitudId)
        .eq('estado', 'pendiente');
    return (rows as List).cast<Map<String, dynamic>>();
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
}
