import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:signature/signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:trazabox/models/solicitud_material.dart';

/// Pantalla de guía de entrega — firmada por entregador Y solicitante.
/// [esEntregador]: true = quien entrega, false = quien recibe.
class GuiaEntregaScreen extends StatefulWidget {
  final SolicitudMaterial solicitud;
  final bool esEntregador;
  final String rutPropio;
  final String nombrePropio;
  final Position? posicion;

  const GuiaEntregaScreen({
    super.key,
    required this.solicitud,
    required this.esEntregador,
    required this.rutPropio,
    required this.nombrePropio,
    this.posicion,
  });

  @override
  State<GuiaEntregaScreen> createState() => _GuiaEntregaScreenState();
}

class _GuiaEntregaScreenState extends State<GuiaEntregaScreen> {
  static const Color _bg      = Color(0xFF0A1628);
  static const Color _surface = Color(0xFF0D1B2A);
  static const Color _accent  = Color(0xFF00D9FF);
  static const Color _border  = Color(0xFF1E3A5F);
  static const Color _textDim = Color(0xFF8FA8C8);
  static const Color _green   = Color(0xFF22C55E);
  static const Color _red     = Color(0xFFEF4444);

  late final SignatureController _firmaCtrl;
  bool _guardando = false;
  bool _paso2     = false;
  String? _guiaId;
  bool _completada = false;

  // Series ingresadas por el entregador
  final List<String>      _series   = [];
  final TextEditingController _serieCtrl = TextEditingController();

  final _db = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _firmaCtrl = SignatureController(
      penStrokeWidth: 2.5,
      penColor: Colors.white,
      exportBackgroundColor: const Color(0xFF0D1B2A),
    );

    if (widget.solicitud.esSeriado && widget.solicitud.series.isNotEmpty) {
      _series.addAll(widget.solicitud.series);
    }

    if (!widget.esEntregador && widget.solicitud.guiaId != null) {
      _paso2 = true;
    }
  }

  @override
  void dispose() {
    _firmaCtrl.dispose();
    _serieCtrl.dispose();
    super.dispose();
  }

  // ── Series ───────────────────────────────────────────────────

  void _agregarSerie(String serie) {
    final s = serie.trim();
    if (s.isEmpty || _series.contains(s)) return;
    setState(() {
      _series.add(s);
      _serieCtrl.clear();
    });
  }

  void _eliminarSerie(String serie) =>
      setState(() => _series.remove(serie));

  Future<void> _escanearCodigo() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => const _BarcodeScannerSheet(),
    );
    if (result != null && result.isNotEmpty) _agregarSerie(result);
  }

  // ── Paso 1: Entregador firma ─────────────────────────────────

  Future<void> _firmarEntregador() async {
    final sol = widget.solicitud;
    if (sol.esSeriado && _series.length < sol.cantidad) {
      _snack(
          'Debes ingresar ${sol.cantidad} serie(s). Tienes ${_series.length}.');
      return;
    }
    if (_firmaCtrl.isEmpty) {
      _snack('Dibuja tu firma primero');
      return;
    }
    setState(() => _guardando = true);
    try {
      final b64 = await _toBase64(_firmaCtrl);

      final now = DateTime.now();
      final guia = await _db.from('solicitudes_bodega').insert({
        'solicitud_id':       sol.id,
        'rut_solicitante':    sol.rutSolicitante,
        'nombre_solicitante': sol.nombreSolicitante,
        'rut_entregador':     widget.rutPropio,
        'nombre_entregador':  widget.nombrePropio,
        'hora':
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:00',
        'fecha':              now.toIso8601String().substring(0, 10),
        'lugar':              _lugarStr(),
        'latitud':            widget.posicion?.latitude,
        'longitud':           widget.posicion?.longitude,
        'detalle_material':   '${sol.cantidad}× ${sol.tipoMaterial}',
        'series':             _series,
        'cantidad':           sol.cantidad,
        'firma_entregador':   b64,
        'estado':             'pendiente',
      }).select().single();

      final guiaId = (guia as Map)['id'] as String;
      _guiaId = guiaId;

      await _db.from('solicitudes_material').update({
        'estado':   'en_guia',
        'guia_id':  guiaId,
        'series':   _series,
      }).eq('id', sol.id);

      _firmaCtrl.clear();
      setState(() {
        _paso2    = true;
        _guardando = false;
      });
    } catch (e) {
      setState(() => _guardando = false);
      _snack('Error: $e');
    }
  }

  // ── Paso 2: Solicitante firma ────────────────────────────────

  Future<void> _firmarSolicitante() async {
    if (_firmaCtrl.isEmpty) {
      _snack('Dibuja tu firma primero');
      return;
    }
    setState(() => _guardando = true);
    try {
      final b64    = await _toBase64(_firmaCtrl);
      final guiaId = _guiaId ?? widget.solicitud.guiaId;

      await _db.from('solicitudes_bodega').update({
        'firma_solicitante': b64,
        'estado':            'firmada',
      }).eq('id', guiaId!);

      await _db.from('solicitudes_material').update({
        'estado': 'completada',
      }).eq('id', widget.solicitud.id);

      setState(() {
        _completada = true;
        _guardando  = false;
      });
    } catch (e) {
      setState(() => _guardando = false);
      _snack('Error: $e');
    }
  }

  String _lugarStr() {
    final p = widget.posicion;
    if (p == null) return 'Sin GPS';
    return '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
  }

  Future<String> _toBase64(SignatureController ctrl) async {
    final img   = await ctrl.toImage();
    final bytes = await img!.toByteData(format: ui.ImageByteFormat.png);
    return base64Encode(bytes!.buffer.asUint8List());
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Guía de Entrega',
            style: TextStyle(color: Colors.white, fontSize: 15)),
      ),
      body: _completada ? _buildConfirmacion() : _buildGuia(),
    );
  }

  // ── Pantalla de confirmación ─────────────────────────────────

  Widget _buildConfirmacion() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle, color: _green, size: 72),
            const SizedBox(height: 20),
            const Text('Guía firmada correctamente',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
                'El registro fue enviado a bodega para confirmar el traspaso.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textDim, fontSize: 13)),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.of(context)
                ..pop()
                ..pop(),
              style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14)),
              child: const Text('Listo',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
      );

  // ── Guía completa ────────────────────────────────────────────

  Widget _buildGuia() {
    final sol = widget.solicitud;
    final now = DateTime.now();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Encabezado ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border)),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              const Icon(Icons.description_outlined, color: _accent, size: 18),
              const SizedBox(width: 8),
              const Text('GUÍA DE ENTREGA DE MATERIAL',
                  style: TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5)),
            ]),
            const Divider(height: 20, color: Color(0xFF1E3A5F)),
            _campo('Fecha',
                '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}'),
            _campo('Hora',
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'),
            _campo('Lugar', _lugarStr()),
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFF1E3A5F)),
            const SizedBox(height: 8),
            _campo('Solicitante', sol.nombreSolicitante),
            _campo('RUT solicitante', sol.rutSolicitante),
            _campo('Entregador',
                sol.nombreEntregador ?? widget.nombrePropio),
            _campo('RUT entregador',
                sol.rutEntregador ?? widget.rutPropio),
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFF1E3A5F)),
            const SizedBox(height: 8),
            _campo('Material', '${sol.cantidad}× ${sol.tipoMaterial}'),
            if (_series.isNotEmpty)
              _campo('Series', _series.join('\n')),
          ]),
        ),

        const SizedBox(height: 16),

        // ── Ingreso de series (solo entregador, paso 1, seriados) ──
        if (widget.esEntregador && !_paso2 && sol.esSeriado)
          _buildSeccionSeries(sol),

        const SizedBox(height: 4),

        // ── Firma ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border)),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(
              _paso2
                  ? 'Firma del solicitante (quien recibe)'
                  : 'Firma del entregador (quien entrega)',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              _paso2
                  ? sol.nombreSolicitante
                  : (sol.nombreEntregador ?? widget.nombrePropio),
              style: const TextStyle(color: _textDim, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Signature(
                controller: _firmaCtrl,
                height: 160,
                backgroundColor: const Color(0xFF111D2E),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              TextButton.icon(
                onPressed: _firmaCtrl.clear,
                icon: const Icon(Icons.clear, size: 14),
                label: const Text('Borrar',
                    style: TextStyle(fontSize: 12)),
                style:
                    TextButton.styleFrom(foregroundColor: _textDim),
              ),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _guardando
                    ? null
                    : (_paso2
                        ? _firmarSolicitante
                        : _firmarEntregador),
                icon: _guardando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black))
                    : const Icon(Icons.check, size: 18),
                label: Text(
                  _guardando
                      ? 'Guardando...'
                      : (_paso2
                          ? 'Confirmar recepción'
                          : 'Confirmar entrega'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _paso2 ? _green : _accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
        ),

        if (!_paso2) ...[
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _accent.withValues(alpha: 0.2))),
            child: const Row(children: [
              Icon(Icons.info_outline, color: _accent, size: 14),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Paso 1 de 2. Después de tu firma, el solicitante debe firmar en su dispositivo.',
                  style: TextStyle(color: _accent, fontSize: 11),
                ),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  // ── Sección de series ────────────────────────────────────────

  Widget _buildSeccionSeries(SolicitudMaterial sol) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.qr_code_scanner, color: _accent, size: 16),
          const SizedBox(width: 8),
          Text(
            'Series a entregar (${_series.length}/${sol.cantidad})',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13),
          ),
        ]),
        const SizedBox(height: 12),

        // Escáner + campo manual
        Row(children: [
          Expanded(
            child: TextField(
              controller: _serieCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Número de serie',
                hintStyle:
                    TextStyle(color: _textDim.withValues(alpha: 0.5)),
                filled: true,
                fillColor: const Color(0xFF0A1628),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Color(0xFF00D9FF)),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                isDense: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              onSubmitted: _agregarSerie,
            ),
          ),
          const SizedBox(width: 8),
          // Botón agregar manual
          InkWell(
            onTap: () => _agregarSerie(_serieCtrl.text),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _accent.withValues(alpha: 0.4))),
              child: const Icon(Icons.add, color: _accent, size: 20),
            ),
          ),
          const SizedBox(width: 6),
          // Botón escáner
          InkWell(
            onTap: _escanearCodigo,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _green.withValues(alpha: 0.4))),
              child: const Icon(Icons.qr_code_scanner,
                  color: _green, size: 20),
            ),
          ),
        ]),

        if (_series.isNotEmpty) ...[
          const SizedBox(height: 10),
          ..._series.map((s) => Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                    color: const Color(0xFF0A1628),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _green.withValues(alpha: 0.3))),
                child: Row(children: [
                  Icon(Icons.check_circle_outline,
                      color: _green, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(s,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontFamily: 'monospace')),
                  ),
                  GestureDetector(
                    onTap: () => _eliminarSerie(s),
                    child: const Icon(Icons.close, color: _red, size: 16),
                  ),
                ]),
              )),
        ],

        if (_series.length < sol.cantidad)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Faltan ${sol.cantidad - _series.length} serie(s)',
              style: TextStyle(
                  color: _red.withValues(alpha: 0.8), fontSize: 11),
            ),
          ),
      ]),
    );
  }

  Widget _campo(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          SizedBox(
            width: 120,
            child: Text('$label:',
                style: const TextStyle(color: _textDim, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ),
        ]),
      );
}

// ── Modal escáner de códigos de barra ────────────────────────

class _BarcodeScannerSheet extends StatefulWidget {
  const _BarcodeScannerSheet();

  @override
  State<_BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<_BarcodeScannerSheet> {
  final MobileScannerController _ctrl = MobileScannerController();
  bool _scanned = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.55,
      child: Column(children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 12),
        const Text('Escanear código de barra',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        const SizedBox(height: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              controller: _ctrl,
              onDetect: (capture) {
                if (_scanned) return;
                final barcode = capture.barcodes.firstOrNull;
                final raw     = barcode?.rawValue;
                if (raw != null && raw.isNotEmpty) {
                  _scanned = true;
                  Navigator.pop(context, raw);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar',
              style: TextStyle(color: Colors.white54)),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}
