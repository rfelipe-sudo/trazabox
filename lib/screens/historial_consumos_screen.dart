import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/traza_consumo_service.dart';

// ── Paleta oscura del módulo historial (diseño "C" aprobado 2026-08-25) ──────
const _bgDark = Color(0xFF101815);
const _cardDark = Color(0xFF18231E);
const _borderDark = Color(0xFF24312B);
const _accent = Color(0xFF2DD894);
const _accentDim = Color(0xFF123527);
const _textPrim = Color(0xFFEAF4EF);
const _textSec = Color(0xFF7E938A);
const _textCap = Color(0xFF6B7F76);

const _nombresMesHist = [
  '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

/// Historial de órdenes consumidas — tema oscuro con cards de mes con anillo
/// de progreso (últimos 6 meses) y buscador de series en todo el histórico.
class HistorialConsumosScreen extends StatefulWidget {
  final int mes;
  final int anno;

  const HistorialConsumosScreen({
    super.key,
    required this.mes,
    required this.anno,
  });

  @override
  State<HistorialConsumosScreen> createState() =>
      _HistorialConsumosScreenState();
}

class _HistorialConsumosScreenState extends State<HistorialConsumosScreen> {
  final _service = TrazaConsumoService();

  String? _rut;
  bool _cargando = true;
  String? _error;

  List<ResumenMesConsumo> _resumen = [];
  late int _mesSel = widget.mes;
  late int _annoSel = widget.anno;

  final Map<String, List<ConsumoDeclarado>> _cachePorMes = {};
  bool _cargandoMes = false;

  List<ConsumoDeclarado> get _consumosMesSel =>
      _cachePorMes['$_annoSel-$_mesSel'] ?? const [];

  /// Máximo de órdenes entre los 6 meses (para el anillo proporcional).
  int get _maxOrdenes => _resumen.fold(0, (m, r) => r.ordenes > m ? r.ordenes : m);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final rut = prefs.getString('rut_tecnico');
      if (rut == null || rut.isEmpty) {
        throw Exception('No hay RUT de técnico en sesión');
      }
      _rut = rut;

      final resumen = await _service.resumenConsumosUltimosMeses(rut);
      if (!mounted) return;
      setState(() {
        _resumen = resumen;
        _cargando = false;
      });
      await _cargarMes(_mesSel, _annoSel);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  Future<void> _cargarMes(int mes, int anno) async {
    final rut = _rut;
    if (rut == null) return;

    setState(() {
      _mesSel = mes;
      _annoSel = anno;
    });

    if (_cachePorMes.containsKey('$anno-$mes')) return;

    setState(() => _cargandoMes = true);
    try {
      final consumos =
          await _service.obtenerConsumosMes(rut, mes: mes, anno: anno);
      if (!mounted) return;
      setState(() {
        _cachePorMes['$anno-$mes'] = consumos;
        _cargandoMes = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cachePorMes['$anno-$mes'] = const [];
        _cargandoMes = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        title: const Text('Historial de Consumos'),
        backgroundColor: _bgDark,
        foregroundColor: _textPrim,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: _borderDark)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: _accent),
            tooltip: 'Buscar serie',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BuscadorSeriesScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando
                ? null
                : () {
                    _cachePorMes.clear();
                    _cargar();
                  },
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _error != null
              ? _buildError()
              : Column(
                  children: [
                    _buildMesesStrip(),
                    Expanded(child: _buildListaMes()),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.orange, size: 48),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textPrim)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _cargar,
              style: FilledButton.styleFrom(backgroundColor: _accent),
              icon: const Icon(Icons.refresh, color: _bgDark),
              label: const Text('Reintentar',
                  style: TextStyle(color: _bgDark)),
            ),
          ],
        ),
      ),
    );
  }

  /// Cards horizontales de los últimos 6 meses, con anillo de progreso.
  Widget _buildMesesStrip() {
    return SizedBox(
      height: 148,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        itemCount: _resumen.length,
        itemBuilder: (_, i) {
          final r = _resumen[i];
          final sel = r.mes == _mesSel && r.anno == _annoSel;
          final progreso =
              _maxOrdenes > 0 ? r.ordenes / _maxOrdenes : 0.0;

          return GestureDetector(
            onTap: () => _cargarMes(r.mes, r.anno),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 122,
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: _cardDark,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: sel ? _accent : _borderDark,
                  width: sel ? 1.6 : 1,
                ),
                boxShadow: sel
                    ? [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.25),
                          blurRadius: 14,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${_nombresMesHist[r.mes].toUpperCase()} ${r.anno % 100}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: sel ? _accent : _textSec,
                    ),
                  ),
                  const SizedBox(height: 9),
                  _AnilloProgreso(
                    progreso: progreso,
                    activo: sel || r.ordenes > 0,
                    child: Text(
                      '${r.ordenes}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: _textPrim,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${r.materiales} materiales',
                    style: const TextStyle(fontSize: 9.5, color: _textCap),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildListaMes() {
    if (_cargandoMes) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }

    final consumos = _consumosMesSel;
    if (consumos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history, color: _textSec, size: 56),
              const SizedBox(height: 16),
              Text(
                'Sin consumos en ${_nombresMesHist[_mesSel]}',
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: _textPrim),
              ),
              const SizedBox(height: 8),
              const Text(
                'Las órdenes que declares aparecerán aquí con su detalle.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textSec, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    // Agrupado por fecha de ejecución de la orden (más reciente primero).
    final porDia = <String, List<ConsumoDeclarado>>{};
    for (final c in consumos) {
      porDia.putIfAbsent(_claveDia(c.fechaTrabajo), () => []).add(c);
    }
    final dias = porDia.keys.toList()..sort((a, b) => b.compareTo(a));

    final items = <Widget>[];
    for (final dia in dias) {
      final lista = porDia[dia]!;
      items.add(_cabeceraDia(dia, lista.length));
      items.addAll(lista.map(_buildCardConsumo));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: items,
    );
  }

  /// Clave ordenable 'YYYY-MM-DD'; sin fecha → '' (queda al final).
  String _claveDia(String fecha) {
    try {
      final d = DateTime.parse(fecha);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  Widget _cabeceraDia(String clave, int cantidad) {
    const diasLargo = ['', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
    String titulo;
    try {
      final d = DateTime.parse(clave);
      titulo = '${diasLargo[d.weekday]} ${d.day} de ${_nombresMesHist[d.month].toLowerCase()}';
    } catch (_) {
      titulo = 'Sin fecha de ejecución';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
      child: Row(
        children: [
          const Icon(Icons.event, size: 14, color: _accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              titulo.toUpperCase(),
              style: const TextStyle(
                color: _textPrim,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _accentDim,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$cantidad ${cantidad == 1 ? 'orden' : 'órdenes'}',
              style: const TextStyle(color: _accent, fontSize: 10.5, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardConsumo(ConsumoDeclarado c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderDark),
      ),
      child: Theme(
        // Quita los divisores por defecto del ExpansionTile
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: _accent.withValues(alpha: 0.08),
        ),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          iconColor: _accent,
          collapsedIconColor: _textSec,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _accentDim,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.check, color: _accent, size: 20),
          ),
          title: Text(
            c.ordenTrabajo,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14.5,
                color: _textPrim),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(c.tipoActividad,
                  style: const TextStyle(color: _accent, fontSize: 11.5)),
              const SizedBox(height: 2),
              Text(
                'Ejec. ${_fechaCorta(c.fechaTrabajo)} · '
                'Cons. ${_fechaHora(c.fechaConsumo)}',
                style: const TextStyle(fontSize: 10.5, color: _textCap),
              ),
            ],
          ),
          trailing: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: _accentDim,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${c.totalItems}',
              style: const TextStyle(
                  color: _accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
          ),
          children: [
            Container(height: 1, color: _borderDark),
            const SizedBox(height: 10),
            if (c.noSeriados.isNotEmpty) ...[
              _tituloSeccion('MATERIALES'),
              const SizedBox(height: 4),
              ...c.noSeriados.map((m) => _filaMaterial(
                    icono: Icons.category_outlined,
                    texto: m['categoria']?.toString() ?? '',
                    detalle: m['nombre']?.toString() ?? '',
                    cantidad: 'x${m['cantidad'] ?? 0}',
                  )),
            ],
            if (c.seriados.isNotEmpty) ...[
              const SizedBox(height: 8),
              _tituloSeccion('EQUIPOS'),
              const SizedBox(height: 4),
              ..._seriadosOrdenados(c.seriados).map((e) => _filaMaterial(
                    icono: Icons.qr_code_2,
                    texto: e['categoria']?.toString() ?? '',
                    detalle: e['nombre']?.toString() ?? '',
                    cantidad: e['serie']?.toString() ?? '',
                    cantidadMono: true,
                  )),
            ],
          ],
        ),
      ),
    );
  }

  /// Mismo orden que la pantalla de selección: ONT → Extensores → Decos.
  List<Map<String, dynamic>> _seriadosOrdenados(
      List<Map<String, dynamic>> seriados) {
    const orden = ['ONT', 'EXTENSOR', 'DECO', 'GATEWAY', 'MTA', 'OTRO'];
    final copia = [...seriados];
    copia.sort((a, b) {
      int idx(Map<String, dynamic> m) {
        final i = orden.indexOf(m['categoria']?.toString() ?? '');
        return i == -1 ? orden.length : i;
      }

      return idx(a).compareTo(idx(b));
    });
    return copia;
  }

  Widget _tituloSeccion(String t) => Align(
        alignment: Alignment.centerLeft,
        child: Text(t,
            style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: _textSec)),
      );

  Widget _filaMaterial({
    required IconData icono,
    required String texto,
    required String detalle,
    required String cantidad,
    bool cantidadMono = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icono, size: 15, color: _textSec),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(texto,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _textPrim)),
                if (detalle.isNotEmpty && detalle != texto)
                  Text(detalle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 10, color: _textCap)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(cantidad,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: _textPrim,
                  fontFamily: cantidadMono ? 'monospace' : null)),
        ],
      ),
    );
  }

  String _fechaCorta(String fecha) {
    const dias = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    try {
      final d = DateTime.parse(fecha);
      return '${dias[d.weekday]} ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    } catch (_) {
      return fecha.isEmpty ? '—' : fecha;
    }
  }

  String _fechaHora(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Anillo de progreso alrededor del contador de órdenes del mes.
class _AnilloProgreso extends StatelessWidget {
  final double progreso;
  final bool activo;
  final Widget child;

  const _AnilloProgreso({
    required this.progreso,
    required this.activo,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 54,
            height: 54,
            child: CircularProgressIndicator(
              value: progreso.clamp(0.0, 1.0),
              strokeWidth: 4.5,
              strokeCap: StrokeCap.round,
              color: activo ? _accent : _borderDark,
              backgroundColor: _borderDark,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

// ── Buscador de series (diseño "A" en oscuro) ───────────────────────────────

/// Busca una serie en TODO el histórico (`equipos_seriados_traza`),
/// sin límite de mes, con filtro segmentado por tipo de equipo.
class BuscadorSeriesScreen extends StatefulWidget {
  const BuscadorSeriesScreen({super.key});

  @override
  State<BuscadorSeriesScreen> createState() => _BuscadorSeriesScreenState();
}

class _BuscadorSeriesScreenState extends State<BuscadorSeriesScreen> {
  final _service = TrazaConsumoService();
  final _controller = TextEditingController();

  /// null = todos. Valores en tabla: ONT | DECO | EXTENSOR
  String? _tipo;
  bool _buscando = false;
  bool _buscoAlgunaVez = false;
  List<SerieEncontrada> _resultados = [];

  static const _segmentos = <String?, String>{
    null: 'Todos',
    'ONT': 'ONT',
    'DECO': 'Deco',
    'EXTENSOR': 'Extensor',
  };

  static const _nombresTipo = <String, String>{
    'ONT': 'ONT',
    'DECO': 'DECO',
    'EXTENSOR': 'EXT',
    'GATEWAY': 'GTW',
    'MTA': 'MTA',
    'OTRO': 'OTRO',
  };

  Color _colorTipo(String tipo) {
    switch (tipo) {
      case 'ONT':
        return const Color(0xFF64B5F6);
      case 'EXTENSOR':
        return const Color(0xFFFFB74D);
      case 'DECO':
        return _accent;
      default:
        return _textSec;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final texto = _controller.text.trim();
    if (texto.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Escribe al menos 4 caracteres de la serie')),
      );
      return;
    }

    setState(() {
      _buscando = true;
      _buscoAlgunaVez = true;
    });
    try {
      final resultados =
          await _service.buscarSeries(texto: texto, tipoEquipo: _tipo);
      if (!mounted) return;
      setState(() {
        _resultados = resultados;
        _buscando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resultados = [];
        _buscando = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error buscando: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        title: const Text('Buscar Serie'),
        backgroundColor: _bgDark,
        foregroundColor: _textPrim,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: _borderDark)),
      ),
      body: Column(
        children: [
          // Campo de búsqueda
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _buscar(),
              style: const TextStyle(
                  color: _textPrim,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1),
              cursorColor: _accent,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.qr_code_2, color: _accent),
                hintText: 'Serie completa o parcial…',
                hintStyle: const TextStyle(
                    color: _textCap, fontFamily: null, letterSpacing: 0),
                filled: true,
                fillColor: _cardDark,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _borderDark, width: 1.4),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _accent, width: 1.6),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search, color: _accent),
                  onPressed: _buscando ? null : _buscar,
                ),
              ),
            ),
          ),

          // Control segmentado
          Container(
            margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: _cardDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderDark),
            ),
            child: Row(
              children: _segmentos.entries.map((e) {
                final sel = _tipo == e.key;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _tipo = e.key);
                      if (_buscoAlgunaVez) _buscar();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? _accentDim : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        e.value,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: sel ? _accent : _textSec,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          Expanded(child: _buildResultados()),
        ],
      ),
    );
  }

  Widget _buildResultados() {
    if (_buscando) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (!_buscoAlgunaVez) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Busca una serie para saber en qué orden de trabajo\n'
            'y por qué técnico fue instalada.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textSec, fontSize: 13),
          ),
        ),
      );
    }
    if (_resultados.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Serie no encontrada en el histórico.\n'
            'Recuerda que el histórico parte desde agosto 2026\n'
            '(lo anterior se carga manualmente).',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textSec, fontSize: 13),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      itemCount: _resultados.length,
      itemBuilder: (_, i) {
        final r = _resultados[i];
        final color = _colorTipo(r.tipoEquipo);
        return Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: _cardDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _borderDark),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      r.serie,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _textPrim,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _nombresTipo[r.tipoEquipo] ?? r.tipoEquipo,
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: color),
                    ),
                  ),
                ],
              ),
              if (r.descripcion.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(r.descripcion,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 11, color: _textPrim)),
              ],
              const SizedBox(height: 4),
              Text(
                'OT ${r.ordenTrabajo} · '
                '${r.fechaTrabajo.isNotEmpty ? r.fechaTrabajo : 'sin fecha'} · '
                'Téc. ${r.rutTecnico}',
                style: const TextStyle(fontSize: 11, color: _textCap),
              ),
            ],
          ),
        );
      },
    );
  }
}
