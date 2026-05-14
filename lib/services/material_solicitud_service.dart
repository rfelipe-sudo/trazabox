import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:trazabox/services/logistica_service.dart';

class MaterialSolicitudService {
  final _db = Supabase.instance.client;

  /// Encuentra técnicos cercanos con stock suficiente y los notifica.
  Future<void> notificarDestinatarios({
    required String solicitudId,
    required String tipoMaterial,
    required double? latSolicitante,
    required double? lngSolicitante,
    required String rutSolicitante,
  }) async {
    // Fetch en paralelo: stock logístico + ubicaciones
    final results = await Future.wait<dynamic>([
      LogisticaService().fetchStock(),
      _db.from('tecnicos_ubicacion').select('tecnico_id, latitud, longitud'),
    ]);
    final stock    = results[0] as List<TecnicoStock>;
    final ubicRows = results[1] as List<dynamic>;

    // Mapa rut → (lat, lng)
    final Map<String, (double, double)> ubicMap = {};
    for (final u in ubicRows) {
      final rut = u['tecnico_id'] as String?;
      final lat = (u['latitud']  as num?)?.toDouble();
      final lng = (u['longitud'] as num?)?.toDouble();
      if (rut != null && lat != null && lng != null) {
        ubicMap[rut] = (lat, lng);
      }
    }

    final esExtensor = tipoMaterial.contains('Extensor');
    final umbral     = esExtensor ? 3.0 : 5.0;

    final List<Map<String, dynamic>> destinatarios = [];

    for (final tecnico in stock) {
      if (tecnico.rut == rutSolicitante) continue;

      final cantidad = tecnico.stock[tipoMaterial] ?? 0;
      if (cantidad <= umbral) continue;

      // Filtro de distancia (solo si tenemos ambas posiciones)
      if (latSolicitante != null && lngSolicitante != null) {
        final pos = ubicMap[tecnico.rut];
        if (pos == null) continue; // sin ubicación conocida → omitir
        final dist = _distanciaKm(latSolicitante, lngSolicitante, pos.$1, pos.$2);
        if (dist > 5.0) continue;
      }

      destinatarios.add({
        'solicitud_id':     solicitudId,
        'rut_tecnico':      tecnico.rut,
        'nombre_tecnico':   tecnico.nombre,
        'stock_disponible': cantidad.toInt(),
        'estado':           'pendiente',
      });
    }

    if (destinatarios.isEmpty) return;

    await _db.from('solicitudes_material_destinatarios').insert(destinatarios);

    // FCM best-effort (un insert por técnico)
    for (final d in destinatarios) {
      try {
        await _db.from('alertas_fcm').upsert({
          'rut_tecnico': d['rut_tecnico'],
          'activa':      true,
          'tipo':        'solicitud_material',
          'descripcion': 'Solicitud de material: $tipoMaterial',
        }, onConflict: 'rut_tecnico');
      } catch (_) {}
    }
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

    // Solo actualiza si todavía está pendiente (evitar race condition)
    await _db.from('solicitudes_material').update({
      'estado':            'aceptada',
      'rut_entregador':    rutAceptador,
      'nombre_entregador': nombreAceptador,
      'lat_entregador':    lat,
      'lng_entregador':    lng,
    }).eq('id', solicitudId).eq('estado', 'pendiente');
  }

  /// Destinatarios que siguen pendientes (para alerta de 10 minutos).
  Future<List<Map<String, dynamic>>> destinatariosPendientes(
      String solicitudId) async {
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
