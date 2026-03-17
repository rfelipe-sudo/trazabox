import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trazabox/models/usuario.dart';
import 'package:trazabox/constants/app_constants.dart';
import 'package:trazabox/services/tecnico_service.dart';

/// Estado del registro del dispositivo
enum RegistroEstado {
  cargando,       // Verificando si está registrado
  noRegistrado,   // Dispositivo nuevo, necesita registro
  registrado,     // Ya registrado, puede entrar
  error,          // Error al verificar
}

/// Provider para manejar autenticación y sesión del usuario
class AuthProvider extends ChangeNotifier {
  Usuario? _usuario;
  Usuario? get usuario => _usuario;
  
  TecnicoData? _tecnico;
  TecnicoData? get tecnico => _tecnico;
  
  bool _isLoading = true;
  bool get isLoading => _isLoading;
  
  RegistroEstado _registroEstado = RegistroEstado.cargando;
  RegistroEstado get registroEstado => _registroEstado;
  
  bool get isAuthenticated => _registroEstado == RegistroEstado.registrado && _usuario != null;
  bool get necesitaRegistro => _registroEstado == RegistroEstado.noRegistrado;
  
  String? _error;
  String? get error => _error;
  
  String? _deviceId;
  String? get deviceId => _deviceId;

  /// Inicializa el provider verificando el registro del dispositivo
  Future<void> initialize() async {
    _isLoading = true;
    _registroEstado = RegistroEstado.cargando;
    notifyListeners();
    
    try {
      // Obtener el device ID
      _deviceId = await TecnicoService.getDeviceId();
      print('📱 Device ID: $_deviceId');
      
      // Verificar si el dispositivo está registrado
      _tecnico = await TecnicoService.verificarRegistro();
      
      if (_tecnico != null) {
        // Dispositivo registrado - crear usuario desde datos del técnico
        _usuario = Usuario(
          id: _tecnico!.deviceId,
          nombre: _tecnico!.nombre,
          telefono: _tecnico!.telefono,
          email: '${_tecnico!.telefono}@crea.cl',
          rol: _tecnico!.esSupervisor ? RolUsuario.supervisor : RolUsuario.tecnico,
          ultimaConexion: DateTime.now(),
        );
        _registroEstado = RegistroEstado.registrado;
        print('✅ Usuario autenticado: ${_usuario!.nombre}');
      } else {
        // Dispositivo no registrado
        _registroEstado = RegistroEstado.noRegistrado;
        print('⚠️ Dispositivo no registrado, mostrando pantalla de registro');
      }
    } catch (e) {
      print('❌ Error inicializando auth: $e');
      _error = 'Error al verificar registro: $e';
      _registroEstado = RegistroEstado.error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Registra el dispositivo con los datos del técnico
  Future<bool> registrarDispositivo({
    required String telefono,
    required String nombre,
    String rol = 'tecnico',
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      // Validaciones
      if (telefono.trim().isEmpty) {
        _error = 'El teléfono es obligatorio';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      if (nombre.trim().isEmpty) {
        _error = 'El nombre es obligatorio';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      // Registrar el técnico
      _tecnico = await TecnicoService.registrarTecnico(
        telefono: telefono.trim(),
        nombre: nombre.trim(),
        rol: rol,
      );
      
      if (_tecnico == null) {
        _error = 'Error al registrar el dispositivo';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      // Crear usuario
      _usuario = Usuario(
        id: _tecnico!.deviceId,
        nombre: _tecnico!.nombre,
        telefono: _tecnico!.telefono,
        email: '${_tecnico!.telefono}@crea.cl',
        rol: _tecnico!.esSupervisor ? RolUsuario.supervisor : RolUsuario.tecnico,
        ultimaConexion: DateTime.now(),
      );
      
      // Guardar sesión
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AppConstants.storageKeyUsuario,
        jsonEncode(_usuario!.toJson()),
      );
      
      _registroEstado = RegistroEstado.registrado;
      _isLoading = false;
      notifyListeners();
      
      print('✅ Registro exitoso: ${_usuario!.nombre}');
      return true;
    } catch (e) {
      _error = 'Error de registro: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Cierra la sesión del usuario (limpia registro local)
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Limpiar registro local
      await TecnicoService.limpiarRegistro();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.storageKeyUsuario);
      
      _usuario = null;
      _tecnico = null;
      _registroEstado = RegistroEstado.noRegistrado;
    } catch (e) {
      print('Error en logout: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Actualiza datos del usuario
  Future<void> actualizarUsuario(Usuario usuario) async {
    _usuario = usuario;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppConstants.storageKeyUsuario,
      jsonEncode(usuario.toJson()),
    );
    
    notifyListeners();
  }
  
  /// Reintentar verificación (para botón de reintentar en error)
  Future<void> reintentar() async {
    await initialize();
  }
}
