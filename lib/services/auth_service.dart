// ============================================================================
// SERVICIO DE AUTENTICACIÓN CON SUPABASE
// ============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Login por RUT - llama get_usuario_por_rut RPC
  Future<Map<String, dynamic>?> loginPorRut(String rut) async {
    try {
      final response = await _client.rpc('get_usuario_por_rut', params: {
        'p_rut': rut,
      });

      if (response == null || response.isEmpty) {
        return null;
      }

      // Guardar en SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final rutStr = response['rut']?.toString() ?? rut;
      final nombreStr = response['nombre']?.toString() ?? '';
      final rolStr = response['rol_nombre']?.toString() ?? 'tecnico';

      await prefs.setString('user_id', response['id']?.toString() ?? '');
      await prefs.setString('user_rut', rutStr);
      await prefs.setString('user_nombre', nombreStr);
      await prefs.setString('user_rol', rolStr);
      await prefs.setString('supervisor_id', response['supervisor_id']?.toString() ?? '');

      if (rolStr == 'supervisor' || rolStr == 'ito') {
        await prefs.setString('rut_supervisor', rutStr);
        await prefs.setString('nombre_supervisor', nombreStr);
      }

      return response;
    } catch (e) {
      print('❌ [AuthService] Error en loginPorRut: $e');
      return null;
    }
  }

  /// Obtener rol guardado
  Future<String> getRol() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_rol') ?? 'tecnico';
  }

  /// Verificar si puede ver equipo (supervisor o ITO)
  Future<bool> puedeVerEquipo() async {
    final rol = await getRol();
    return rol == 'supervisor' || rol == 'ito';
  }

  /// Obtener ID del usuario actual
  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  /// Obtener supervisor_id del usuario actual
  Future<String?> getSupervisorId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('supervisor_id');
  }

  /// Obtener nombre del usuario actual
  Future<String> getNombre() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_nombre') ?? '';
  }

  /// Logout - limpiar datos
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    await prefs.remove('user_rut');
    await prefs.remove('user_nombre');
    await prefs.remove('user_rol');
    await prefs.remove('supervisor_id');
    await prefs.remove('rut_supervisor');
    await prefs.remove('nombre_supervisor');
    await prefs.remove('historial_id_activo');
  }
}













