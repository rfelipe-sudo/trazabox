import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Modelo de datos del técnico
class TecnicoData {
  final String deviceId;
  final String telefono;
  final String nombre;
  final String rol;
  /// Cuerpo del RUT solo dígitos (sin DV), opcional
  final String? rutCuerpo;
  final DateTime createdAt;

  TecnicoData({
    required this.deviceId,
    this.telefono = '',
    required this.nombre,
    this.rol = 'tecnico',
    this.rutCuerpo,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory TecnicoData.fromJson(Map<String, dynamic> json) {
    return TecnicoData(
      deviceId: json['device_id'] ?? '',
      telefono: json['telefono'] ?? '',
      nombre: json['nombre'] ?? '',
      rol: json['rol'] ?? 'tecnico',
      rutCuerpo: json['rut_cuerpo'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'telefono': telefono,
    'nombre': nombre,
    'rol': rol,
    if (rutCuerpo != null) 'rut_cuerpo': rutCuerpo,
    'created_at': createdAt.toIso8601String(),
  };

  bool get esTecnico => rol == 'tecnico';
  bool get esSupervisor => rol == 'supervisor';
}

/// Servicio para manejar el registro automático de técnicos
class TecnicoService {
  static const String _storageKey = 'tecnico_registrado';
  static final SupabaseClient _supabase = Supabase.instance.client;
  
  // Simular base de datos local (en producción sería el backend)
  static final Map<String, TecnicoData> _mockDatabase = {};

  /// Obtiene el Android ID del dispositivo
  static Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    
    // El Android ID es único por dispositivo
    final androidId = androidInfo.id;
    print('📱 Android ID obtenido: $androidId');
    return androidId;
  }

  /// Verifica si el dispositivo ya está registrado
  /// Retorna los datos del técnico si existe, null si no
  static Future<TecnicoData?> verificarRegistro() async {
    try {
      final deviceId = await getDeviceId();
      
      // Primero verificar en storage local
      final prefs = await SharedPreferences.getInstance();
      final tecnicoJson = prefs.getString(_storageKey);
      
      if (tecnicoJson != null) {
        final tecnico = TecnicoData.fromJson(jsonDecode(tecnicoJson));
        if (tecnico.deviceId == deviceId) {
          print('✅ Técnico encontrado en storage local: ${tecnico.nombre}');
          return tecnico;
        }
      }
      
      // Simular llamada al backend: GET /tecnico/{device_id}
      // En producción: final response = await http.get('/tecnico/$deviceId');
      if (_mockDatabase.containsKey(deviceId)) {
        final tecnico = _mockDatabase[deviceId]!;
        // Guardar en storage local para próximas consultas
        await _guardarEnLocal(tecnico);
        print('✅ Técnico encontrado en servidor: ${tecnico.nombre}');
        return tecnico;
      }
      
      print('❌ Dispositivo no registrado: $deviceId');
      return null;
    } catch (e) {
      print('❌ Error verificando registro: $e');
      return null;
    }
  }

  /// Registra un nuevo técnico
  static Future<TecnicoData?> registrarTecnico({
    String telefono = '',
    required String nombre,
    String rol = 'tecnico',
    String? rutCuerpo,
  }) async {
    try {
      final deviceId = await getDeviceId();
      
      final tecnico = TecnicoData(
        deviceId: deviceId,
        telefono: telefono,
        nombre: nombre,
        rol: rol,
        rutCuerpo: rutCuerpo,
      );
      
      // Simular llamada al backend: POST /tecnico
      // En producción: final response = await http.post('/tecnico', body: tecnico.toJson());
      _mockDatabase[deviceId] = tecnico;
      
      // Guardar en storage local
      await _guardarEnLocal(tecnico);
      
      print('✅ Técnico registrado: ${tecnico.nombre}');
      return tecnico;
    } catch (e) {
      print('❌ Error registrando técnico: $e');
      return null;
    }
  }

  /// Guarda los datos del técnico en storage local
  static Future<void> _guardarEnLocal(TecnicoData tecnico) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(tecnico.toJson()));
  }

  /// Elimina el registro local (para pruebas/desarrollo)
  static Future<void> limpiarRegistro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    print('🧹 Registro local limpiado');
  }

  /// Obtiene el device ID actual
  static Future<String> obtenerDeviceIdActual() async {
    return await getDeviceId();
  }

  /// Valida el RUT contra técnicos y supervisores.
  /// PRIMERO revisa `supervisores_traza` (prioridad); si no está, revisa `tecnicos_traza_zc`.
  /// Así usuarios que están en ambas tablas (ej: ex-técnicos ahora supervisores) se ven como supervisor.
  /// Retorna mapa con 'nombre', 'rol', 'tipo_contrato' o null si no existe.
  static Future<Map<String, dynamic>?> validarRutEnProduccion(String rut) async {
    try {
      print('🔍 [ValidarRUT] ════════════════════════════════');
      print('🔍 [ValidarRUT] RUT: "$rut"');

      // ── 1. PRIMERO buscar en supervisores ────────────────────
      final respSup = await _supabase
          .from('supervisores_traza')
          .select('rut, nombre, cargo, activo')
          .eq('rut', rut)
          .eq('activo', true)
          .limit(1)
          .maybeSingle();

      if (respSup != null) {
        final nombreSup = respSup['nombre']?.toString() ?? 'Supervisor';
        final cargo = (respSup['cargo']?.toString() ?? 'supervisor').trim().toLowerCase();
        final rol = cargo.contains('ito') ? 'ito' : 'supervisor';
        print('✅ [ValidarRUT] Supervisor encontrado: $nombreSup | cargo: $cargo');
        return {
          'rut': rut,
          'nombre': nombreSup.isNotEmpty ? nombreSup : 'Supervisor',
          'existe': true,
          'rol': rol,
          'tipo_contrato': 'supervisor',
        };
      }

      // ── 2. Si no es supervisor, buscar en técnicos ───────────
      print('🔍 [ValidarRUT] No encontrado en supervisores. Revisando técnicos...');
      final respTec = await _supabase
          .from('tecnicos_traza_zc')
          .select('rut, nombre_completo, activo, tipo_contrato')
          .eq('rut', rut)
          .eq('activo', true)
          .limit(1)
          .maybeSingle();

      if (respTec != null && respTec['nombre_completo'] != null) {
        final nombre = respTec['nombre_completo'].toString();
        final tipoContrato = respTec['tipo_contrato']?.toString() ?? 'nuevo';
        print('✅ [ValidarRUT] Técnico encontrado: $nombre');
        return {
          'rut': rut,
          'nombre': nombre,
          'existe': true,
          'rol': 'tecnico',
          'tipo_contrato': tipoContrato,
        };
      }

      print('❌ [ValidarRUT] RUT no encontrado: $rut');
      print('🔍 [ValidarRUT] ════════════════════════════════');
      return null;
    } catch (e) {
      print('❌ [ValidarRUT] Error: $e');
      return null;
    }
  }
}
