import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trazabox/providers/auth_provider.dart';
import 'package:trazabox/services/ayuda_service.dart';
import 'package:trazabox/services/trazabox_password_service.dart';

/// Pantalla para confirmar la contraseña TrazaBox al iniciar sesión en el dispositivo.
class DesbloqueoAppScreen extends StatefulWidget {
  const DesbloqueoAppScreen({super.key});

  @override
  State<DesbloqueoAppScreen> createState() => _DesbloqueoAppScreenState();
}

class _DesbloqueoAppScreenState extends State<DesbloqueoAppScreen> {
  final _pwd = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _rut;

  @override
  void initState() {
    super.initState();
    _cargarRut();
  }

  Future<void> _cargarRut() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _rut = prefs.getString('rut_tecnico'));
  }

  @override
  void dispose() {
    _pwd.dispose();
    super.dispose();
  }

  Future<void> _ingresar() async {
    final rut = _rut?.trim();
    if (rut == null || rut.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay RUT guardado. Cierra sesión y vuelve a registrarte.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final pass = _pwd.text.trim();
    if (pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa tu contraseña'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await TrazaboxPasswordService().login(rut, pass);
      if (!mounted) return;

      if (!res.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.mensajeUsuario.isNotEmpty
                ? res.mensajeUsuario
                : 'Contraseña incorrecta'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (res.mustChangePassword) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debes definir una contraseña nueva desde registro.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      context.read<AuthProvider>().marcarSesionDesbloqueada();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cambiarDeUsuario() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B2A),
        title: const Text('Cambiar de usuario', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Se borrará la sesión de este dispositivo y podrás ingresar con otro RUT.',
          style: TextStyle(color: Color(0xFF8FA8C8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B35)),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    AyudaService().detenerMonitoreoGlobal();
    await context.read<AuthProvider>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final nombre = auth.usuario?.nombre ?? 'Usuario';

    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              const Icon(Icons.lock_outline, size: 64, color: Color(0xFF00D9FF)),
              const SizedBox(height: 24),
              Text(
                'Hola, $nombre',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _rut != null ? 'RUT: $_rut' : 'Cargando…',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8FA8C8), fontSize: 14),
              ),
              const SizedBox(height: 32),
              const Text(
                'Ingresa tu contraseña TrazaBox para continuar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8FA8C8), fontSize: 15),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _pwd,
                obscureText: _obscure,
                onSubmitted: (_) => _loading ? null : _ingresar(),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  labelStyle: const TextStyle(color: Color(0xFF8FA8C8)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: const Color(0xFF00D9FF),
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF0D1B2A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF00D9FF), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _ingresar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D9FF),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF1E3A5F),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('DESBLOQUEAR', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: _loading ? null : _cambiarDeUsuario,
                child: const Text(
                  'Cambiar de usuario',
                  style: TextStyle(color: Color(0xFF8FA8C8), decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
