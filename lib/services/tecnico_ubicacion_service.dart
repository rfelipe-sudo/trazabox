import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Publica la ubicación del técnico en `tecnicos_ubicacion` (tracking tipo
/// Uber) mientras la app está abierta: al iniciar y cada 5 minutos.
///
/// El matching de solicitudes de material parte de esta tabla (en_linea +
/// GPS con menos de 10 min): sin estas filas nadie recibe notificaciones.
class TecnicoUbicacionService {
  TecnicoUbicacionService._();

  static Timer? _timer;
  static String? _rut;
  static String? _nombre;

  /// Arranca la publicación periódica. Idempotente: llamadas repetidas
  /// reinician el timer sin duplicarlo.
  static Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    _rut = prefs.getString('rut_tecnico') ?? prefs.getString('rut');
    _nombre = prefs.getString('nombre_tecnico') ?? 'Técnico';
    if (_rut == null || _rut!.isEmpty) return;

    await _publicar();
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _publicar(),
    );
  }

  static Future<void> _publicar() async {
    final rut = _rut;
    if (rut == null || rut.isEmpty) return;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));

      await Supabase.instance.client.from('tecnicos_ubicacion').upsert({
        'tecnico_id': rut,
        'nombre': _nombre,
        'latitud': pos.latitude,
        'longitud': pos.longitude,
        'estado': 'disponible',
        'ultima_actualizacion': DateTime.now().toUtc().toIso8601String(),
        'en_linea': true,
      }, onConflict: 'tecnico_id');
      debugPrint('📍 [Ubicacion] publicada $rut '
          '(${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)})');
    } catch (e) {
      debugPrint('⚠️ [Ubicacion] no publicada: $e');
    }
  }

  /// Marca offline y detiene el timer (al cerrar sesión / app).
  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final rut = _rut;
    if (rut == null || rut.isEmpty) return;
    try {
      await Supabase.instance.client
          .from('tecnicos_ubicacion')
          .update({
            'en_linea': false,
            'ultima_actualizacion': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('tecnico_id', rut);
    } catch (_) {}
  }
}
