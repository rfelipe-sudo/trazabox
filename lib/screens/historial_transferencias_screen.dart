import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:trazabox/services/guia_pdf_service.dart';

/// Historial de traspasos de material del técnico (como solicitante o
/// entregador), agrupado por mes y fecha, con acceso a la guía PDF de
/// respaldo de cada transferencia (regenerada desde `solicitudes_bodega`).
class HistorialTransferenciasScreen extends StatefulWidget {
  final String rut;

  const HistorialTransferenciasScreen({super.key, required this.rut});

  @override
  State<HistorialTransferenciasScreen> createState() =>
      _HistorialTransferenciasScreenState();
}

class _HistorialTransferenciasScreenState
    extends State<HistorialTransferenciasScreen> {
  static const Color _bg      = Color(0xFF0A1628);
  static const Color _surface = Color(0xFF0D1B2A);
  static const Color _accent  = Color(0xFF00D9FF);
  static const Color _border  = Color(0xFF1E3A5F);
  static const Color _textDim = Color(0xFF8FA8C8);
  static const Color _green   = Color(0xFF22C55E);
  static const Color _orange  = Color(0xFFF59E0B);

  static const _meses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  final _db = Supabase.instance.client;

  bool _cargando = true;
  List<Map<String, dynamic>> _rows = [];
  String? _generandoGuiaId;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final rows = await _db
          .from('solicitudes_material')
          .select()
          .eq('estado', 'completada')
          .or('rut_solicitante.eq.${widget.rut},rut_entregador.eq.${widget.rut}')
          .order('created_at', ascending: false)
          .limit(300);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(rows as List);
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando historial: $e')));
    }
  }

  Future<void> _abrirGuia(Map<String, dynamic> sol) async {
    final guiaId = sol['guia_id'] as String?;
    if (guiaId == null || guiaId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Esta transferencia no tiene guía asociada')));
      return;
    }
    setState(() => _generandoGuiaId = sol['id'] as String);
    try {
      final guiaRow = await _db
          .from('solicitudes_bodega')
          .select()
          .eq('id', guiaId)
          .maybeSingle();
      if (guiaRow == null) {
        throw Exception('guía no encontrada');
      }
      final erpId = (sol['traspaso_erp_id'] as num?)?.toInt();
      final bytes = await GuiaPdfService.generar(
        guia: guiaRow,
        traspasoErpId: erpId != null && erpId > 0 ? erpId : null,
      );
      if (!mounted) return;
      setState(() => _generandoGuiaId = null);
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            backgroundColor: _bg,
            appBar: AppBar(
              backgroundColor: _surface,
              iconTheme: const IconThemeData(color: Colors.white),
              title: const Text('Guía de entrega',
                  style: TextStyle(color: Colors.white, fontSize: 15)),
            ),
            body: PdfPreview(
              build: (_) async => bytes,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              pdfFileName:
                  'guia_entrega_${(sol['id'] as String).substring(0, 8)}.pdf',
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _generandoGuiaId = null);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo generar la guía: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Historial de transferencias',
            style: TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _rows.isEmpty
              ? const Center(
                  child: Text('Aún no tienes transferencias completadas',
                      style: TextStyle(color: _textDim, fontSize: 13)))
              : _buildLista(),
    );
  }

  Widget _buildLista() {
    // Agrupar por mes (yyyy-MM), preservando el orden descendente
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final r in _rows) {
      final f = DateTime.parse(r['created_at'] as String).toLocal();
      final clave = '${f.year}-${f.month.toString().padLeft(2, '0')}';
      grupos.putIfAbsent(clave, () => []).add(r);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final entry in grupos.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Row(children: [
              Text(
                '${_meses[int.parse(entry.key.substring(5)) - 1]} '
                '${entry.key.substring(0, 4)}',
                style: const TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.5),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Container(height: 1, color: _border)),
              const SizedBox(width: 8),
              Text('${entry.value.length}',
                  style: const TextStyle(color: _textDim, fontSize: 12)),
            ]),
          ),
          ...entry.value.map(_buildItem),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildItem(Map<String, dynamic> sol) {
    final f = DateTime.parse(sol['created_at'] as String).toLocal();
    final fecha =
        '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')} '
        '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';

    final soyEntregador = sol['rut_entregador'] == widget.rut;
    final rol      = soyEntregador ? 'ENTREGADO' : 'RECIBIDO';
    final rolColor = soyEntregador ? _orange : _green;
    final otro = soyEntregador
        ? (sol['nombre_solicitante'] as String? ?? sol['rut_solicitante'])
        : (sol['nombre_entregador'] as String? ??
            sol['rut_entregador'] ??
            '—');

    final series = (sol['series'] as List?)?.map((e) => e.toString()).toList()
        ?? const <String>[];
    final erpId = (sol['traspaso_erp_id'] as num?)?.toInt();
    final generando = _generandoGuiaId == sol['id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: rolColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border:
                  Border.all(color: rolColor.withValues(alpha: 0.4)),
            ),
            child: Text(rol,
                style: TextStyle(
                    color: rolColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${sol['cantidad']}× ${sol['tipo_material']}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(fecha,
              style: const TextStyle(color: _textDim, fontSize: 11)),
        ]),
        const SizedBox(height: 8),
        Text(
          soyEntregador ? 'Para: $otro' : 'De: $otro',
          style: const TextStyle(color: _textDim, fontSize: 12),
        ),
        if (series.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Series: ${series.join(', ')}',
                style: const TextStyle(
                    color: _textDim,
                    fontSize: 11,
                    fontFamily: 'monospace')),
          ),
        if (erpId != null && erpId > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Traspaso ERP N° $erpId',
                style: const TextStyle(color: _textDim, fontSize: 11)),
          ),
        if (sol['guia_id'] != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: generando ? null : () => _abrirGuia(sol),
              icon: generando
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _accent))
                  : const Icon(Icons.picture_as_pdf, size: 15),
              label: Text(generando ? 'Generando…' : 'Ver guía de respaldo',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: BorderSide(color: _accent.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 9),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
