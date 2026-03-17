import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/calidad_traza_service.dart';
import '../widgets/creaciones_loading.dart';

class CalidadDetalleScreen extends StatefulWidget {
  const CalidadDetalleScreen({super.key});

  @override
  State<CalidadDetalleScreen> createState() => _CalidadDetalleScreenState();
}

class _CalidadDetalleScreenState extends State<CalidadDetalleScreen> {
  final CalidadTrazaService _service = CalidadTrazaService();

  bool _cargando = true;
  String? _tecnicoRut;

  // Calidad por período
  Map<String, dynamic>? _calFeb;
  Map<String, dynamic>? _calMar;
  Map<String, dynamic>? _calAbr;

  late String _periodoFeb;
  late String _periodoMar;
  late String _periodoAbr;

  @override
  void initState() {
    super.initState();
    _periodoFeb = _service.getPeriodoCerrado();
    _periodoMar = _service.getPeriodoMidiendo();
    _periodoAbr = _service.getPeriodoProximo();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    final prefs = await SharedPreferences.getInstance();
    _tecnicoRut = prefs.getString('rut_tecnico');

    if (_tecnicoRut == null) {
      setState(() => _cargando = false);
      return;
    }

    try {
      final resultados = await Future.wait([
        _service.obtenerCalidadPorPeriodo(_tecnicoRut!, _periodoFeb),
        _service.obtenerCalidadPorPeriodo(_tecnicoRut!, _periodoMar),
        _service.obtenerCalidadPorPeriodo(_tecnicoRut!, _periodoAbr),
      ]);

      if (mounted) {
        setState(() {
          _calFeb = resultados[0] as Map<String, dynamic>?;
          _calMar = resultados[1] as Map<String, dynamic>?;
          _calAbr = resultados[2] as Map<String, dynamic>?;
          _cargando = false;
        });
      }
    } catch (e) {
      print('❌ [CalidadDetalle] Error: $e');
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Mi Calidad',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarDatos,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CreacionesLoading())
          : _tecnicoRut == null
              ? const Center(
                  child: Text(
                    'No se encontró RUT del técnico',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    await _cargarDatos();
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Gráfico de evolución
                        _buildEvolucionChart(),
                        const SizedBox(height: 16),

                        // BONO FEB — cerrado
                        _buildBonoCard(
                          periodo: _periodoFeb,
                          calidad: _calFeb,
                          estado: _EstadoBono.cerrado,
                        ),
                        const SizedBox(height: 12),

                        // BONO MAR — midiendo
                        _buildBonoCard(
                          periodo: _periodoMar,
                          calidad: _calMar,
                          estado: _EstadoBono.midiendo,
                        ),
                        const SizedBox(height: 12),

                        // BONO ABR — próximo o midiendo según datos
                        _buildBonoCard(
                          periodo: _periodoAbr,
                          calidad: _calAbr,
                          estado: _calAbr != null
                              ? _EstadoBono.midiendo
                              : _EstadoBono.proximo,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
    );
  }

  // ── Gráfico de evolución ───────────────────────────────────────────────────

  Widget _buildEvolucionChart() {
    final pctFeb = (_calFeb?['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;
    final pctMar = (_calMar?['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;
    final pctAbr = (_calAbr?['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;

    final puntos = [
      _PuntoEvolucion(
        label: 'BONO ${_service.getNombreBono(_periodoFeb)}',
        pct: pctFeb,
        tieneData: _calFeb != null,
      ),
      _PuntoEvolucion(
        label: 'BONO ${_service.getNombreBono(_periodoMar)}',
        pct: pctMar,
        tieneData: _calMar != null,
      ),
      _PuntoEvolucion(
        label: 'BONO ${_service.getNombreBono(_periodoAbr)}',
        pct: pctAbr,
        tieneData: _calAbr != null,
      ),
    ];

    return Card(
      color: Colors.grey[850],
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.show_chart, color: Colors.cyan, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Evolución del Reiterado',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 130,
              child: CustomPaint(
                painter: _EvolucionChartPainter(puntos: puntos),
                size: Size.infinite,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: puntos.map((p) {
                final color = p.tieneData ? _colorCalidad(p.pct) : Colors.grey[600]!;
                return Column(
                  children: [
                    Text(
                      p.label,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[400],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.tieneData ? '${p.pct.toStringAsFixed(1)}%' : '—',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Card de bono con ranking embebido ────────────────────────────────────

  Widget _buildBonoCard({
    required String periodo,
    required Map<String, dynamic>? calidad,
    required _EstadoBono estado,
  }) {
    final nombreBono = _service.getNombreBono(periodo);
    final infoPeriodo = _service.getInfoPeriodo(periodo);

    final pct = (calidad?['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;
    final reiterados = (calidad?['total_reiterados'] as num?)?.toInt() ?? 0;
    final completadas = (calidad?['total_completadas'] as num?)?.toInt() ?? 0;
    final detalle = List<Map<String, dynamic>>.from(
      (calidad?['detalle'] as List?) ?? [],
    );

    final colorPct = _colorCalidad(pct);
    final sinDatos = calidad == null;

    return Card(
      color: Colors.grey[850],
      elevation: 2,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: _iconoEstado(estado),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'BONO $nombreBono',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                _badgeEstado(estado),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              infoPeriodo['periodo_texto'] ?? '',
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
            Text(
              infoPeriodo['fin_garantia_texto'] ?? '',
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
          ],
        ),
        trailing: sinDatos
            ? Text('Sin datos', style: TextStyle(fontSize: 12, color: Colors.grey[500]))
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${pct.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: colorPct,
                    ),
                  ),
                  Text(
                    '$reiterados/$completadas',
                    style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                  ),
                ],
              ),
        children: sinDatos
            ? [_buildSinDatosMsg(estado)]
            : [
                // Resumen métricas
                _buildResumenMetricas(pct, reiterados, completadas, colorPct),
                const SizedBox(height: 16),

                // Detalle reiterados
                if (detalle.isNotEmpty) ...[
                  Text(
                    'Reiterados detalle',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...detalle.map((d) => _buildDetalleReiterado(d)),
                ] else
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        '¡Sin reiterados! 🎉',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ),
                  ),
              ],
      ),
    );
  }

  // ── Widgets auxiliares ─────────────────────────────────────────────────────

  Widget _buildResumenMetricas(
    double pct,
    int reiterados,
    int completadas,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _metricaItem('${pct.toStringAsFixed(1)}%', 'Reiteración', color),
          Container(width: 1, height: 30, color: Colors.grey[700]),
          _metricaItem('$reiterados', 'Reiterados', Colors.orange),
          Container(width: 1, height: 30, color: Colors.grey[700]),
          _metricaItem('$completadas', 'Completadas', Colors.white),
        ],
      ),
    );
  }

  Widget _metricaItem(String valor, String label, Color color) {
    return Column(
      children: [
        Text(
          valor,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[400])),
      ],
    );
  }

  Widget _buildSinDatosMsg(_EstadoBono estado) {
    final msg = estado == _EstadoBono.proximo
        ? 'Aún no hay registros para este período.\nLos datos aparecerán cuando el trabajo comience.'
        : 'No hay datos para este período.';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(
          msg,
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildDetalleReiterado(Map<String, dynamic> d) {
    final ordenOriginal = d['orden_de_trabajo']?.toString() ?? '';
    final fechaOriginal = d['fecha']?.toString() ?? '';
    final ordenReiterada = d['reiterada_por_ot']?.toString() ?? '';
    final fechaReiterada = d['reiterada_por_fecha']?.toString() ?? '';
    final tecnicoReiterado = d['reiterada_por_tecnico']?.toString() ?? '';
    final cliente = d['cliente']?.toString() ?? '';
    final direccion = d['direccion']?.toString() ?? '';
    final tipoActividad = d['tipo_de_actividad']?.toString() ?? '';

    int dias = 0;
    final orig = _parseFecha(fechaOriginal);
    final reit = _parseFecha(fechaReiterada);
    if (orig != null && reit != null) {
      dias = reit.difference(orig).inDays.abs();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _badge(ordenOriginal, Colors.green),
              const SizedBox(width: 8),
              Text(
                _service.formatearFecha(fechaOriginal),
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
              if (tipoActividad.isNotEmpty) ...[
                const Spacer(),
                Text(tipoActividad,
                    style: TextStyle(fontSize: 9, color: Colors.grey[500])),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _badge(ordenReiterada.isNotEmpty ? ordenReiterada : 'Sin OT', Colors.orange),
              const SizedBox(width: 8),
              Text(
                _service.formatearFecha(fechaReiterada),
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
              const Spacer(),
              _badge('$dias días', Colors.red),
            ],
          ),
          if (cliente.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('👤 $cliente',
                style: TextStyle(fontSize: 10, color: Colors.grey[400])),
          ],
          if (direccion.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('📍 $direccion',
                style: TextStyle(fontSize: 10, color: Colors.grey[400])),
          ],
          if (tecnicoReiterado.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('🔧 $tecnicoReiterado',
                style: TextStyle(fontSize: 10, color: Colors.orange[300])),
          ],
        ],
      ),
    );
  }

  Widget _badge(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _iconoEstado(_EstadoBono estado) {
    switch (estado) {
      case _EstadoBono.cerrado:
        return const Icon(Icons.lock, color: Colors.grey, size: 26);
      case _EstadoBono.midiendo:
        return const Icon(Icons.hourglass_top, color: Colors.amber, size: 26);
      case _EstadoBono.proximo:
        return const Icon(Icons.schedule, color: Colors.cyan, size: 26);
    }
  }

  Widget _badgeEstado(_EstadoBono estado) {
    switch (estado) {
      case _EstadoBono.cerrado:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey[700],
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('Cerrado',
              style: TextStyle(fontSize: 9, color: Colors.white70)),
        );
      case _EstadoBono.midiendo:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('Midiendo',
              style: TextStyle(
                  fontSize: 9,
                  color: Colors.amber,
                  fontWeight: FontWeight.bold)),
        );
      case _EstadoBono.proximo:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.cyan.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('En trabajo',
              style: TextStyle(
                  fontSize: 9,
                  color: Colors.cyan,
                  fontWeight: FontWeight.bold)),
        );
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  DateTime? _parseFecha(String fecha) {
    try {
      final p = fecha.split('/');
      if (p.length == 3) {
        final d = int.parse(p[0]);
        final m = int.parse(p[1]);
        final a = p[2].length == 2 ? 2000 + int.parse(p[2]) : int.parse(p[2]);
        return DateTime(a, m, d);
      }
    } catch (_) {}
    return null;
  }

  Color _colorCalidad(double pct) {
    if (pct <= 4.0) return Colors.green;
    if (pct <= 5.7) return Colors.orange;
    return Colors.red;
  }

}

// ── Enum estado de bono ────────────────────────────────────────────────────

enum _EstadoBono { cerrado, midiendo, proximo }

// ── Datos para el gráfico ──────────────────────────────────────────────────

class _PuntoEvolucion {
  final String label;
  final double pct;
  final bool tieneData;
  const _PuntoEvolucion({
    required this.label,
    required this.pct,
    required this.tieneData,
  });
}

// ── Painter del gráfico de evolución ──────────────────────────────────────

class _EvolucionChartPainter extends CustomPainter {
  final List<_PuntoEvolucion> puntos;
  const _EvolucionChartPainter({required this.puntos});

  @override
  void paint(Canvas canvas, Size size) {
    if (puntos.isEmpty) return;

    const padLeft = 36.0;
    const padRight = 16.0;
    const padTop = 12.0;
    const padBottom = 20.0;

    final chartW = size.width - padLeft - padRight;
    final chartH = size.height - padTop - padBottom;

    // Valor máximo para la escala Y — mínimo 6% para que haya espacio
    final maxVal = puntos
        .where((p) => p.tieneData)
        .map((p) => p.pct)
        .fold(6.0, (a, b) => math.max(a, b)) *
        1.2;

    // Grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.07)
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = padTop + chartH * (1 - i / 4);
      canvas.drawLine(
        Offset(padLeft, y),
        Offset(padLeft + chartW, y),
        gridPaint,
      );
      // Label Y
      final label = '${(maxVal * i / 4).toStringAsFixed(1)}%';
      _drawText(
        canvas,
        label,
        Offset(0, y - 5),
        Colors.grey.withOpacity(0.5),
        8,
      );
    }

    // Puntos en coordenadas de pantalla
    final coords = <Offset>[];
    for (int i = 0; i < puntos.length; i++) {
      final x = padLeft + chartW * (i / (puntos.length - 1).clamp(1, 99));
      final yNorm = puntos[i].tieneData ? puntos[i].pct / maxVal : 0.0;
      final y = padTop + chartH * (1 - yNorm.clamp(0.0, 1.0));
      coords.add(Offset(x, y));
    }

    // Área bajo la curva (solo puntos con datos)
    final hasData = puntos.where((p) => p.tieneData).length;
    if (hasData >= 2) {
      final areaPath = Path();
      bool primero = true;
      for (int i = 0; i < puntos.length; i++) {
        if (!puntos[i].tieneData) continue;
        if (primero) {
          areaPath.moveTo(coords[i].dx, coords[i].dy);
          primero = false;
        } else {
          areaPath.lineTo(coords[i].dx, coords[i].dy);
        }
      }
      // Cerrar al fondo
      Offset? ultimo;
      Offset? primeroCoord;
      for (int i = 0; i < puntos.length; i++) {
        if (puntos[i].tieneData) {
          ultimo = coords[i];
          primeroCoord ??= coords[i];
        }
      }
      if (ultimo != null && primeroCoord != null) {
        areaPath.lineTo(ultimo.dx, padTop + chartH);
        areaPath.lineTo(primeroCoord.dx, padTop + chartH);
        areaPath.close();
      }
      canvas.drawPath(
        areaPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.cyan.withOpacity(0.18),
              Colors.cyan.withOpacity(0.0),
            ],
          ).createShader(
            Rect.fromLTWH(padLeft, padTop, chartW, chartH),
          ),
      );
    }

    // Línea
    final linePath = Path();
    bool firstLine = true;
    for (int i = 0; i < puntos.length; i++) {
      if (!puntos[i].tieneData) continue;
      if (firstLine) {
        linePath.moveTo(coords[i].dx, coords[i].dy);
        firstLine = false;
      } else {
        linePath.lineTo(coords[i].dx, coords[i].dy);
      }
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = Colors.cyan.withOpacity(0.7)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Puntos y etiquetas X
    for (int i = 0; i < puntos.length; i++) {
      final p = puntos[i];
      final cx = coords[i].dx;
      final cy = coords[i].dy;

      // Etiqueta X
      _drawText(
        canvas,
        p.label.split(' ').last, // solo el mes (FEB, MAR, ABR)
        Offset(cx - 12, padTop + chartH + 4),
        Colors.grey.withOpacity(0.6),
        9,
      );

      if (!p.tieneData) continue;

      // Círculo del punto
      canvas.drawCircle(
        Offset(cx, cy),
        5,
        Paint()..color = _colorCalidadStatic(p.pct),
      );
      canvas.drawCircle(
        Offset(cx, cy),
        5,
        Paint()
          ..color = Colors.white.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

      // Valor sobre el punto
      _drawText(
        canvas,
        '${p.pct.toStringAsFixed(1)}%',
        Offset(cx - 14, cy - 16),
        Colors.white.withOpacity(0.85),
        10,
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double fontSize,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  static Color _colorCalidadStatic(double pct) {
    if (pct <= 4.0) return Colors.green;
    if (pct <= 5.7) return Colors.orange;
    return Colors.red;
  }

  @override
  bool shouldRepaint(covariant _EvolucionChartPainter old) =>
      old.puntos != puntos;
}
