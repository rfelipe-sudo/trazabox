import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/remuneraciones_service.dart';
import '../services/calidad_traza_service.dart';

class AnexoRemuneracionesScreen extends StatefulWidget {
  const AnexoRemuneracionesScreen({super.key});

  @override
  State<AnexoRemuneracionesScreen> createState() =>
      _AnexoRemuneracionesScreenState();
}

class _AnexoRemuneracionesScreenState extends State<AnexoRemuneracionesScreen> {
  final _service = RemuneracionesService();
  final _calidadService = CalidadTrazaService();

  String _rut = '';
  String _nombre = '';
  String _tipoContrato = 'nuevo';
  bool _cargandoInicial = true;

  final List<String> _meses = [];
  // mes → { data, statusCode, errorMsg, cargando, generando }
  final Map<String, Map<String, dynamic>> _periodos = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final rut = prefs.getString('rut_tecnico') ?? '';
    final nombre = prefs.getString('nombre_tecnico') ??
        prefs.getString('nombre') ?? '';
    final tipo = await _calidadService.obtenerTipoContrato(rut, prefs: prefs);
    final meses = RemuneracionesService.ultimosMeses(3);

    setState(() {
      _rut = rut;
      _nombre = nombre;
      _tipoContrato = tipo;
      _meses.addAll(meses);
      _cargandoInicial = false;
      for (final m in meses) {
        _periodos[m] = {
          'data': null,
          'statusCode': -1,
          'errorMsg': '',
          'cargando': true,
          'generando': false,
        };
      }
    });

    await Future.wait(meses.map(_cargarPeriodo));
  }

  Future<void> _cargarPeriodo(String mes) async {
    setState(() => _periodos[mes]!['cargando'] = true);
    final result = await _service.obtenerBonosTecnico(
      rut: _rut,
      tipoContrato: _tipoContrato,
      mes: mes,
    );
    if (!mounted) return;
    setState(() {
      _periodos[mes] = {
        'data': result.data,
        'statusCode': result.statusCode,
        'errorMsg': result.errorMsg,
        'cargando': false,
        'generando': false,
      };
      if (_nombre.isEmpty && result.data != null) {
        _nombre = result.data!['nombre']?.toString() ?? '';
      }
    });
  }

  Future<void> _descargarPdf(String mes) async {
    setState(() => _periodos[mes]!['generando'] = true);
    try {
      final result = await _service.descargarAnexoPdf(rut: _rut, mes: mes);
      if (!mounted) return;

      if (result.bytes != null) {
        final label = _nombreMes(mes).replaceAll(' ', '_');
        await Printing.sharePdf(
          bytes: result.bytes!,
          filename: 'Anexo_TRAZA_$label.pdf',
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se pudo descargar el PDF: ${result.errorMsg}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _periodos[mes]!['generando'] = false);
    }
  }

  String _nombreMes(String mes) {
    final parts = mes.split('-');
    if (parts.length != 2) return mes;
    final m = int.tryParse(parts[1]) ?? 0;
    const nombres = [
      '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo',
      'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];
    return m >= 1 && m <= 12 ? '${nombres[m]} ${parts[0]}' : mes;
  }

  String _pesos(num? v) {
    if (v == null || v == 0) return '\$0';
    final s = v.toInt().abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '\$${buf.toString()}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a2234),
      appBar: AppBar(
        title: const Text('Anexo de Remuneraciones'),
        backgroundColor: const Color(0xFF1a2234),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _cargandoInicial
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderTecnico(),
                  const SizedBox(height: 20),
                  Text(
                    'PERÍODOS DISPONIBLES',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._meses.map(_buildPeriodoCard),
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderTecnico() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF243555),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: Colors.blueAccent, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nombre.isNotEmpty ? _nombre : 'Cargando...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _rut,
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
              ],
            ),
          ),
        ]),
      );

  Widget _buildPeriodoCard(String mes) {
    final p = _periodos[mes] ?? {};
    final cargando = p['cargando'] == true;
    final generando = p['generando'] == true;
    final data = p['data'] as Map<String, dynamic>?;
    final statusCode = p['statusCode'] as int? ?? -1;
    final errorMsg = p['errorMsg'] as String? ?? '';
    final hayError = !cargando && statusCode != 200 && statusCode != -1 && statusCode != 0;
    final sinConexion = !cargando && statusCode == 0;
    final sinDatos = !cargando && statusCode == 200 && data == null;
    final hayDatos = data != null;

    final totalLiquido = hayDatos
        ? (_tipoContrato == 'antiguo'
                ? (data['gran_total_liquido'] ?? data['bono_total_liquido'] ?? 0)
                : (data['total_bono_liquido'] ?? 0))
            as num
        : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF243555),
        borderRadius: BorderRadius.circular(12),
        border: hayError || sinConexion
            ? Border.all(color: Colors.red.withValues(alpha: 0.5))
            : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _buildBadge(
            cargando: cargando,
            hayError: hayError,
            sinDatos: sinDatos,
            sinConexion: sinConexion,
            statusCode: statusCode,
          ),
          const Spacer(),
          if (sinConexion || hayError)
            IconButton(
              onPressed: () => _cargarPeriodo(mes),
              icon: const Icon(Icons.refresh, color: Colors.white54, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Reintentar',
            )
          else
            const Icon(Icons.picture_as_pdf, color: Colors.white38, size: 22),
        ]),
        const SizedBox(height: 10),
        Text(
          _nombreMes(mes),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (cargando) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(
            color: Colors.blueAccent,
            backgroundColor: Colors.white12,
          ),
        ],
        if ((sinConexion || hayError) && errorMsg.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            errorMsg,
            style: TextStyle(color: Colors.orange[300], fontSize: 10),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (hayDatos && totalLiquido > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Líquido: ${_pesos(totalLiquido)}',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (cargando || generando || !hayDatos)
                ? null
                : () => _descargarPdf(mes),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BCD4),
              disabledBackgroundColor: const Color(0xFF2a3a55),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: generando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download, color: Colors.white, size: 18),
            label: Text(
              generando ? 'Descargando...' : 'Descargar PDF',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildBadge({
    required bool cargando,
    required bool hayError,
    required bool sinDatos,
    required bool sinConexion,
    required int statusCode,
  }) {
    if (cargando) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.grey,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('Cargando...',
            style: TextStyle(color: Colors.white, fontSize: 10)),
      );
    }
    if (sinConexion) return _badge('Sin conexión', Colors.orange);
    if (hayError) return _badge('Error $statusCode', Colors.red);
    if (sinDatos) return _badge('Sin datos', Colors.grey);
    return _badge('PAGADO', Colors.green);
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      );
}
