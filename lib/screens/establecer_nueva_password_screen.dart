import 'package:flutter/material.dart';
import 'package:trazabox/services/trazabox_password_service.dart';

/// Pantalla para definir contraseña definitiva tras el primer acceso (ultimos 4 del RUT).
class EstablecerNuevaPasswordScreen extends StatefulWidget {
  const EstablecerNuevaPasswordScreen({
    super.key,
    required this.rut,
    required this.initialPassword,
    required this.onSuccess,
  });

  final String rut;
  final String initialPassword;
  final VoidCallback onSuccess;

  @override
  State<EstablecerNuevaPasswordScreen> createState() =>
      _EstablecerNuevaPasswordScreenState();
}

class _EstablecerNuevaPasswordScreenState
    extends State<EstablecerNuevaPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nueva = TextEditingController();
  final _confirmar = TextEditingController();
  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  void dispose() {
    _nueva.dispose();
    _confirmar.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final svc = TrazaboxPasswordService();
      final res = await svc.setInitialPassword(
        rut: widget.rut,
        initialPassword: widget.initialPassword,
        newPassword: _nueva.text.trim(),
      );

      if (!mounted) return;

      if (!res.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.mensajeUsuario),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      Navigator.of(context).pop(true);
      widget.onSuccess();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        foregroundColor: Colors.white,
        title: const Text('Nueva contraseña'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Define una contraseña segura (mínimo 8 caracteres). '
                  'La usarás en los próximos accesos.',
                  style: TextStyle(color: Color(0xFF8FA8C8), fontSize: 15),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _nueva,
                  obscureText: _obscure1,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration(
                    label: 'Nueva contraseña',
                    suffix: IconButton(
                      icon: Icon(
                        _obscure1
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: const Color(0xFF00D9FF),
                      ),
                      onPressed: () =>
                          setState(() => _obscure1 = !_obscure1),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().length < 8) {
                      return 'Mínimo 8 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmar,
                  obscureText: _obscure2,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration(
                    label: 'Confirmar contraseña',
                    suffix: IconButton(
                      icon: Icon(
                        _obscure2
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: const Color(0xFF00D9FF),
                      ),
                      onPressed: () =>
                          setState(() => _obscure2 = !_obscure2),
                    ),
                  ),
                  validator: (v) {
                    if (v != _nueva.text) {
                      return 'Las contraseñas no coinciden';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _guardar,
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
                        : const Text(
                            'GUARDAR CONTRASEÑA',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration({
    required String label,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF8FA8C8)),
      filled: true,
      fillColor: const Color(0xFF0D1B2A),
      suffixIcon: suffix,
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
    );
  }
}
