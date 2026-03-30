import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trazabox/constants/app_colors.dart';
import 'package:trazabox/providers/auth_provider.dart';
import 'package:trazabox/services/auth_service.dart';
import 'package:trazabox/services/tecnico_service.dart';
import 'package:trazabox/services/trazabox_password_service.dart';
import 'package:trazabox/screens/establecer_nueva_password_screen.dart';

/// Contraseña inicial: últimos 4 dígitos del cuerpo del RUT (antes del guión).
String? passwordInicialDesdeRut(String rut) {
  final s = rut.trim().replaceAll('.', '');
  final i = s.indexOf('-');
  if (i <= 0) return null;
  final cuerpo = s.substring(0, i).replaceAll(RegExp(r'[^0-9]'), '');
  if (cuerpo.isEmpty) return null;
  if (cuerpo.length <= 4) return cuerpo;
  return cuerpo.substring(cuerpo.length - 4);
}

/// Cuerpo numérico del RUT sin puntos ni guión (solo dígitos antes del DV).
String? cuerpoNumericoRut(String rut) {
  final s = rut.trim().replaceAll('.', '');
  final i = s.indexOf('-');
  final head = i > 0 ? s.substring(0, i) : s.replaceAll(RegExp(r'[\-kK]'), '');
  final digits = head.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? null : digits;
}

class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _rutController = TextEditingController();
  bool _isLoading = false;
  bool _validandoRut = false;
  String? _nombreEncontrado;
  bool _rutValido = false;
  String _tipoContrato = 'nuevo';
  String _rolEncontrado = 'tecnico';
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _rutController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cargarDatosGuardados();
  }

  Future<void> _cargarDatosGuardados() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final rutGuardado = prefs.getString('rut_tecnico');

    if (rutGuardado != null) {
      _rutController.text = rutGuardado;
      await _validarRut(rutGuardado); // Auto-validar RUT guardado
    }
  }

  /// Valida el RUT contra la base de datos de producción
  Future<void> _validarRut(String rut) async {
    if (rut.trim().isEmpty) return;

    if (!mounted) return;
    setState(() {
      _validandoRut = true;
      _nombreEncontrado = null;
      _rutValido = false;
    });

    final resultado = await TecnicoService.validarRutEnProduccion(rut.trim());

    if (!mounted) return;
    setState(() {
      _validandoRut = false;
      if (resultado != null) {
        _nombreEncontrado = resultado['nombre'];
        _rutValido = true;
        _tipoContrato = resultado['tipo_contrato']?.toString() ?? 'nuevo';
        _rolEncontrado = resultado['rol']?.toString() ?? 'tecnico';
      } else {
        _nombreEncontrado = null;
        _rutValido = false;
        _tipoContrato = 'nuevo';
      }
    });
  }

  Future<void> _registrar() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Validar que el RUT sea válido
    if (!_rutValido || _nombreEncontrado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ RUT no encontrado en producción'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final rut = _rutController.text.trim();

    setState(() => _isLoading = true);

    try {
      final pwdSvc = TrazaboxPasswordService();
      final loginRes = await pwdSvc.login(rut, _passwordController.text.trim());

      if (!loginRes.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(loginRes.mensajeUsuario),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (loginRes.mustChangePassword) {
        final initialPwd = _passwordController.text.trim();
        if (!mounted) return;
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (ctx) => EstablecerNuevaPasswordScreen(
              rut: rut,
              initialPassword: initialPwd,
              onSuccess: () => _completarRegistroTrasPassword(rut),
            ),
          ),
        );
        return;
      }

      await _completarRegistroTrasPassword(rut);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Registro local del dispositivo + preferencias + navegación (contraseña ya validada en Supabase).
  Future<void> _completarRegistroTrasPassword(String rut) async {
    final auth = context.read<AuthProvider>();
    final authService = AuthService();

    await authService.loginPorRut(rut);

    final rutCuerpo = cuerpoNumericoRut(rut);
    final success = await auth.registrarDispositivo(
      nombre: _nombreEncontrado!,
      rutCuerpo: rutCuerpo,
      rol: _rolEncontrado,
    );

    if (success) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('rut_tecnico', rut);
      await prefs.setString('tipo_contrato', _tipoContrato);
      await prefs.setString('user_rol', _rolEncontrado);
      if (_rolEncontrado == 'supervisor' || _rolEncontrado == 'ito') {
        await prefs.setString('rut_supervisor', rut);
        await prefs.setString('nombre_supervisor', _nombreEncontrado ?? '');
      }
    }

    if (!mounted) return;

    if (!success) {
      final msg = auth.error ?? 'Error al registrar';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.alertUrgent,
        ),
      );
      throw Exception(msg);
    }

    // Siempre AppWrapper: desbloqueo por contraseña y ruteo por rol (supervisor → Mi Equipo).
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                
                // Logo/Icono
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00D9FF), Color(0xFF0099CC)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00D9FF).withOpacity(0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.engineering,
                    size: 50,
                    color: Colors.white,
                  ),
                ).animate().fadeIn().scale(),
                
                const SizedBox(height: 32),
                
                // Título
                const Text(
                  'Registro de Técnico',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 200.ms),
                
                const SizedBox(height: 8),
                
                const Text(
                  'Ingresa tus datos para vincular\neste dispositivo a tu cuenta',
                  style: TextStyle(
                    color: Color(0xFF8FA8C8),
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 300.ms),
                
                const SizedBox(height: 48),
                
                // Campo RUT
                _buildTextField(
                  controller: _rutController,
                  label: 'RUT del Técnico',
                  hint: '14246477-2',
                  icon: Icons.badge,
                  keyboardType: TextInputType.text,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d\-kK]')),
                  ],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El RUT es obligatorio';
                    }
                    if (!RegExp(r'^\d{7,8}[\-]?[\dkK]$').hasMatch(value.trim())) {
                      return 'Formato de RUT inválido';
                    }
                    if (!_rutValido) {
                      return 'RUT no encontrado en producción';
                    }
                    return null;
                  },
                  onChanged: (value) {
                    // Validar RUT cuando se ingresa completo
                    if (RegExp(r'^\d{7,8}[\-]?[\dkK]$').hasMatch(value.trim())) {
                      _validarRut(value);
                    }
                  },
                  suffixIcon: _validandoRut
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF00D9FF),
                            ),
                          ),
                        )
                      : _rutValido
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                ).animate().fadeIn(delay: 400.ms).slideX(begin: -0.1),
                
                const SizedBox(height: 16),
                
                // Mostrar nombre encontrado
                if (_nombreEncontrado != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D3B2F),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person, color: Colors.green),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Técnico encontrado:',
                                style: TextStyle(
                                  color: Color(0xFF7FD99D),
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                _nombreEncontrado!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn().scale(),
                
                if (_nombreEncontrado != null) const SizedBox(height: 20),
                
                // Contraseña: primera vez = 4 últimos del RUT; si ya la cambiaste en Supabase, la nueva.
                _buildTextField(
                  controller: _passwordController,
                  label: 'Contraseña',
                  hint: 'Primer acceso: 4 últimos dígitos del RUT antes del guión',
                  icon: Icons.lock_outline,
                  keyboardType: TextInputType.visiblePassword,
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: const Color(0xFF00D9FF),
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa la contraseña';
                    }
                    if (value.trim().length < 4) {
                      return 'Mínimo 4 caracteres';
                    }
                    return null;
                  },
                ).animate().fadeIn(delay: 500.ms).slideX(begin: -0.1),
                
                const SizedBox(height: 40),
                
                // Botón Registrar
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _registrar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D9FF),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF1E3A5F),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'INGRESAR',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                  ),
                ).animate().fadeIn(delay: 600.ms).scale(begin: const Offset(0.95, 0.95)),
                
                const SizedBox(height: 24),
                
                // Nota sobre la contraseña inicial
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF162942),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1E3A5F)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFF00D9FF),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'La primera vez que entras, Supabase valida los 4 últimos números del RUT antes del guión; luego debes crear una contraseña nueva (mín. 8 caracteres). Si ya la creaste, ingresa esa contraseña.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 700.ms),
                
                const SizedBox(height: 40),
                
                // Device ID (para debug)
                if (auth.deviceId != null)
                  Text(
                    'ID: ${auth.deviceId!.substring(0, 8)}...',
                    style: const TextStyle(
                      color: Color(0xFF5C7A99),
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 800.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    Widget? suffixIcon,
    bool obscureText = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8FA8C8),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          obscureText: obscureText,
          inputFormatters: inputFormatters,
          validator: validator,
          onChanged: onChanged,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: Color(0xFF5C7A99),
            ),
            prefixIcon: Icon(
              icon,
              color: const Color(0xFF00D9FF),
            ),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFF0D1B2A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF00D9FF), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF6B35)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF6B35), width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
