import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:trazabox/models/solicitud_material.dart';
import 'package:trazabox/services/material_solicitud_service.dart';

/// Pantalla que muestra B (entregador) para ingresar el PIN de 6 dígitos
/// que el solicitante (A) recibió en su pantalla. Devuelve `true` por
/// Navigator.pop cuando el PIN fue validado; `false` si la solicitud
/// quedó cancelada (intentos agotados o cancelación remota).
class PinEntryScreen extends StatefulWidget {
  final SolicitudMaterial solicitud;

  const PinEntryScreen({super.key, required this.solicitud});

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  static const Color _bg     = Color(0xFF0A1628);
  static const Color _card   = Color(0xFF112240);
  static const Color _accent = Color(0xFF00D4AA);
  static const Color _danger = Color(0xFFE53935);

  final _db = Supabase.instance.client;

  String _pin          = '';
  bool _cargando       = false;
  String? _error;
  bool _sinIntentos    = false;
  bool _pinVerificado  = false;
  String? _avisoRenovacion;

  StreamSubscription<List<Map<String, dynamic>>>? _subEstado;

  @override
  void initState() {
    super.initState();
    _suscribirEstado();
  }

  @override
  void dispose() {
    _subEstado?.cancel();
    super.dispose();
  }

  void _suscribirEstado() {
    _subEstado = _db
        .from('solicitudes_material')
        .stream(primaryKey: ['id'])
        .eq('id', widget.solicitud.id)
        .listen((rows) {
      if (rows.isEmpty || !mounted || _pinVerificado) return;
      final estado = rows.first['estado'] as String?;
      if (estado == 'cancelada' && !_sinIntentos) {
        _subEstado?.cancel();
        Navigator.pop(context, false);
      }
    });
  }

  Future<void> _regenerarPin({String? aviso}) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await MaterialSolicitudService().generarPin(
        solicitudId: widget.solicitud.id,
        rutSolicitante: widget.solicitud.rutSolicitante,
        forzarNuevo: true,
      );
      if (mounted) {
        setState(() {
          _cargando = false;
          _pin = '';
          _avisoRenovacion = aviso ??
              'PIN renovado. Pide al solicitante el código nuevo en su pantalla.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo renovar el PIN. Intenta nuevamente.';
        });
      }
    }
  }

  void _presionar(String digito) {
    if (_pin.length >= 6 || _cargando || _pinVerificado || _sinIntentos) return;
    setState(() {
      _pin += digito;
      _error = null;
    });
    if (_pin.length == 6) _verificar();
  }

  void _borrar() {
    if (_pin.isEmpty || _cargando || _pinVerificado || _sinIntentos) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _verificar() async {
    if (_pinVerificado) return;
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final raw = await _db.rpc('confirmar_traspaso_pin', params: {
        'p_solicitud_id': widget.solicitud.id,
        'p_pin': _pin,
      });
      final result = raw is Map<String, dynamic>
          ? raw
          : Map<String, dynamic>.from(raw as Map);
      debugPrint('[PIN] resultado: $result');

      if (result['ok'] == true) {
        _pinVerificado = true;
        _subEstado?.cancel();
        if (mounted) Navigator.pop(context, true);
        return;
      }

      final motivo = result['error'] as String? ?? 'error';
      final intentos = result['intentos_restantes'] as int?;

      if (motivo == 'expirado') {
        await _regenerarPin(
            aviso:
                'El PIN anterior expiró. Se generó uno nuevo — pídeselo al solicitante.');
        return;
      }

      final agotados = motivo == 'sin_intentos' ||
          motivo == 'cancelada' ||
          (intentos != null && intentos <= 0);
      setState(() {
        _cargando = false;
        _pin = '';
        _sinIntentos = agotados;
        _error = agotados ? null : _mensajeError(motivo, intentos);
      });
    } catch (e) {
      debugPrint('[PIN] error verificar: $e');
      final msg = e.toString();
      setState(() {
        _cargando = false;
        _pin = '';
        _error =
            'No se pudo confirmar: ${msg.length > 120 ? '${msg.substring(0, 120)}…' : msg}';
      });
    }
  }

  String _mensajeError(String motivo, int? intentos) {
    switch (motivo) {
      case 'pin_ya_usado':
        return 'PIN ya utilizado. Si no ves confirmación, contacta a soporte.';
      case 'ya_completada':
        return 'La solicitud ya fue completada.';
      case 'incorrecto':
        if (intentos != null && intentos > 0) {
          return 'PIN incorrecto. Quedan $intentos intento${intentos == 1 ? '' : 's'}.';
        }
        return 'PIN incorrecto. Sin intentos restantes.';
      default:
        return 'Error inesperado ($motivo).';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _sinIntentos,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Debes confirmar el PIN para cerrar el traspaso.'),
            duration: Duration(seconds: 3),
          ),
        );
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _card,
          automaticallyImplyLeading: false,
          title: const Text('Confirmar traspaso',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ),
        body: _sinIntentos ? _buildSinIntentos() : _buildForm(),
      ),
    );
  }

  Widget _buildSinIntentos() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cancel_outlined, color: _danger, size: 80),
            const SizedBox(height: 24),
            const Text(
              'El traspaso no pudo completarse.',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Se agotaron los intentos de PIN. La solicitud quedó cancelada '
              'y deberán iniciar el proceso desde el principio.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _danger,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 40, vertical: 14)),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver al inicio',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      children: [
        Container(
          color: _card,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, color: _accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pide al solicitante el PIN de 6 dígitos que ve en su pantalla.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        if (_avisoRenovacion != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.refresh, color: _accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _avisoRenovacion!,
                      style: const TextStyle(color: _accent, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 40),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            final filled = i < _pin.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? _accent : Colors.transparent,
                border: Border.all(
                    color: filled
                        ? _accent
                        : Colors.white.withValues(alpha: 0.4),
                    width: 2),
              ),
            );
          }),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_error!,
                style: const TextStyle(color: _danger, fontSize: 13),
                textAlign: TextAlign.center),
          ),
        ],
        const Spacer(),
        if (_cargando)
          const Padding(
            padding: EdgeInsets.only(bottom: 60),
            child: CircularProgressIndicator(color: _accent),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              children: [
                for (final fila in [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                  ['', '0', '⌫'],
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: fila.map((d) {
                        if (d.isEmpty) return const SizedBox(width: 80);
                        final esBorrar = d == '⌫';
                        return _Tecla(
                          label: d,
                          onTap: esBorrar ? _borrar : () => _presionar(d),
                          color: esBorrar
                              ? Colors.white.withValues(alpha: 0.1)
                              : _card,
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Tecla extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _Tecla({
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 64,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
