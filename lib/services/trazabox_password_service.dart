import 'package:supabase_flutter/supabase_flutter.dart';

/// Resultado del intento de login con RUT + contraseña (RPC `trazabox_login`).
class TrazaboxLoginResult {
  final bool success;
  final bool mustChangePassword;
  final String mensajeUsuario;

  const TrazaboxLoginResult({
    required this.success,
    required this.mustChangePassword,
    required this.mensajeUsuario,
  });
}

/// Resultado de establecer contraseña inicial (RPC `trazabox_set_password_inicial`).
class TrazaboxPasswordChangeResult {
  final bool success;
  final String mensajeUsuario;

  const TrazaboxPasswordChangeResult({
    required this.success,
    required this.mensajeUsuario,
  });
}

/// Autenticación por contraseña vía RPC en Supabase (tabla `trazabox_credenciales`).
class TrazaboxPasswordService {
  TrazaboxPasswordService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _rpcLogin = 'trazabox_login';
  static const String _rpcSetInitial = 'trazabox_set_password_inicial';

  Future<TrazaboxLoginResult> login(String rut, String password) async {
    try {
      final raw = await _client.rpc(
        _rpcLogin,
        params: {
          'p_rut': rut.trim(),
          'p_password': password,
        },
      );
      final map = Map<String, dynamic>.from(raw as Map);
      final ok = map['success'] == true;
      final must = map['must_change_password'] == true;
      final msg = (map['message'] ?? map['error'])?.toString() ?? '';
      return TrazaboxLoginResult(
        success: ok,
        mustChangePassword: must,
        mensajeUsuario: ok
            ? ''
            : (msg.isNotEmpty ? msg : 'No se pudo iniciar sesión'),
      );
    } catch (e, st) {
      print('❌ [TrazaboxPasswordService] login: $e\n$st');
      return TrazaboxLoginResult(
        success: false,
        mustChangePassword: false,
        mensajeUsuario: _mensajeAmigable(e),
      );
    }
  }

  Future<TrazaboxPasswordChangeResult> setInitialPassword({
    required String rut,
    required String initialPassword,
    required String newPassword,
  }) async {
    try {
      final raw = await _client.rpc(
        _rpcSetInitial,
        params: {
          'p_rut': rut.trim(),
          'p_password_actual': initialPassword,
          'p_password_nuevo': newPassword,
        },
      );
      final map = Map<String, dynamic>.from(raw as Map);
      final ok = map['success'] == true;
      final msg = (map['message'] ?? map['error'])?.toString() ?? '';
      return TrazaboxPasswordChangeResult(
        success: ok,
        mensajeUsuario: ok
            ? ''
            : (msg.isNotEmpty ? msg : 'No se pudo cambiar la contraseña'),
      );
    } catch (e, st) {
      print('❌ [TrazaboxPasswordService] setInitialPassword: $e\n$st');
      return TrazaboxPasswordChangeResult(
        success: false,
        mensajeUsuario: _mensajeAmigable(e),
      );
    }
  }

  String _mensajeAmigable(Object e) {
    if (e is PostgrestException) {
      final m = e.message;
      if (m.contains('gen_salt') || m.contains('pgcrypto')) {
        return 'Error del servidor al guardar la contraseña. '
            'Ejecuta en Supabase el script SUPABASE_TRAZABOX_PASSWORD_RPC.sql '
            '(extensión pgcrypto y funciones).';
      }
      return m.isNotEmpty ? m : 'Error al comunicarse con el servidor';
    }
    return 'No se pudo completar la operación. Intenta de nuevo.';
  }
}
