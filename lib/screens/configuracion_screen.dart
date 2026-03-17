import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _rutController = TextEditingController();
  final _nombreKeplerController = TextEditingController();
  bool _cargando = true;
  bool _guardando = false;
  String _rolSeleccionado = 'tecnico';

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _rutController.dispose();
    _nombreKeplerController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    
    final prefs = await SharedPreferences.getInstance();
    final rutGuardado = prefs.getString('rut_tecnico');
    final nombreKeplerGuardado = prefs.getString('nombre_tecnico');
    final rolGuardado = prefs.getString('rol_usuario');
    
    setState(() {
      _rutController.text = rutGuardado ?? '';
      _nombreKeplerController.text = nombreKeplerGuardado ?? '';
      _rolSeleccionado = rolGuardado ?? 'tecnico';
      _cargando = false;
    });
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _guardando = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Guardar RUT
      if (_rutController.text.trim().isNotEmpty) {
        await prefs.setString('rut_tecnico', _rutController.text.trim());
      } else {
        await prefs.remove('rut_tecnico');
      }
      
      // Guardar nombre técnico de Kepler
      if (_nombreKeplerController.text.trim().isNotEmpty) {
        await prefs.setString('nombre_tecnico', _nombreKeplerController.text.trim());
      } else {
        await prefs.remove('nombre_tecnico');
      }

      // Guardar rol
      await prefs.setString('rol_usuario', _rolSeleccionado);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Configuración guardada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  Future<void> _cargarValoresPrueba() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nombre_tecnico', 'Oscar Martinez');
    await prefs.setString('rut_tecnico', '14246477-2');
    await prefs.setString('rol_usuario', 'tecnico');
    
    setState(() {
      _rutController.text = '14246477-2';
      _nombreKeplerController.text = 'Oscar Martinez';
      _rolSeleccionado = 'tecnico';
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Valores de prueba cargados'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración Técnico'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Información
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Estos datos se usan para procesar la sabana de Kepler y calcular métricas de producción.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Campo RUT
                    _buildTextField(
                      controller: _rutController,
                      label: 'RUT Técnico',
                      hint: '14246477-2',
                      icon: Icons.badge,
                      keyboardType: TextInputType.text,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d\-kK]')),
                      ],
                      validator: (value) {
                        if (value != null && value.trim().isNotEmpty) {
                          if (!RegExp(r'^\d{7,8}[\-]?[\dkK]$').hasMatch(value.trim())) {
                            return 'Formato de RUT inválido';
                          }
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Campo Nombre en Kepler
                    _buildTextField(
                      controller: _nombreKeplerController,
                      label: 'Nombre en Kepler',
                      hint: 'Oscar Martinez',
                      icon: Icons.account_circle,
                      textCapitalization: TextCapitalization.words,
                      validator: (value) {
                        // Opcional
                        return null;
                      },
                    ),

                    const SizedBox(height: 24),

                    // Selector de Rol
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rol de Usuario',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<String>(
                          segments: [
                            ButtonSegment<String>(
                              value: 'tecnico',
                              label: const Text('Técnico'),
                              icon: const Icon(Icons.engineering),
                            ),
                            ButtonSegment<String>(
                              value: 'bodeguero',
                              label: const Text('Bodeguero'),
                              icon: const Icon(Icons.warehouse),
                            ),
                          ],
                          selected: {_rolSeleccionado},
                          onSelectionChanged: (Set<String> newSelection) {
                            setState(() {
                              _rolSeleccionado = newSelection.first;
                            });
                          },
                          style: SegmentedButton.styleFrom(
                            backgroundColor: Colors.grey[100],
                            foregroundColor: Colors.black87,
                            selectedBackgroundColor: Colors.indigo,
                            selectedForegroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Botón Guardar
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _guardando ? null : _guardar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _guardando
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'GUARDAR CONFIGURACIÓN',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Botón Cargar Valores de Prueba
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _cargarValoresPrueba,
                        icon: const Icon(Icons.science),
                        label: const Text('Cargar Valores de Prueba'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                          side: const BorderSide(color: Colors.blue),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Valores actuales
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Valores Actuales',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.badge, size: 16, color: Colors.grey),
                                const SizedBox(width: 8),
                                Text(
                                  'RUT: ${_rutController.text.isEmpty ? "No configurado" : _rutController.text}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.account_circle, size: 16, color: Colors.grey),
                                const SizedBox(width: 8),
                                Text(
                                  'Nombre: ${_nombreKeplerController.text.isEmpty ? "No configurado" : _nombreKeplerController.text}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  _rolSeleccionado == 'tecnico' ? Icons.engineering : Icons.warehouse,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Rol: ${_rolSeleccionado == 'tecnico' ? 'Técnico' : 'Bodeguero'}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey[50],
          ),
        ),
      ],
    );
  }
}
