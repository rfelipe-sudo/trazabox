import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/consumo_reglas.dart';
import '../services/kepler_sabana_service.dart';
import '../services/traza_consumo_service.dart';
import 'historial_consumos_screen.dart';

const _nombresMesConsumo = [
  '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

/// Menú del consumo del mes: dos accesos —
/// órdenes pendientes de consumo e historial de órdenes consumidas.
class ConsumoMaterialesScreen extends StatefulWidget {
  /// Mes y año a mostrar. Si no se indican, se usa el mes actual.
  final int? mes;
  final int? anno;

  const ConsumoMaterialesScreen({super.key, this.mes, this.anno});

  @override
  State<ConsumoMaterialesScreen> createState() =>
      _ConsumoMaterialesScreenState();
}

class _ConsumoMaterialesScreenState extends State<ConsumoMaterialesScreen> {
  final _service = TrazaConsumoService();

  late final int _mes = widget.mes ?? DateTime.now().month;
  late final int _anno = widget.anno ?? DateTime.now().year;

  bool _cargando = true;
  int _pendientes = 0;
  int _consumidas = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final rut = prefs.getString('rut_tecnico') ?? '';
      if (rut.isEmpty) throw Exception('Sin RUT en sesión');

      final results = await Future.wait([
        _service.contarPendientesMes(rut: rut, mes: _mes, anno: _anno),
        _service.obtenerConsumosMes(rut, mes: _mes, anno: _anno),
      ]);
      if (!mounted) return;
      setState(() {
        _pendientes = results[0] as int;
        _consumidas = (results[1] as List).length;
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Consumo · ${_nombresMesConsumo[_mes]}'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _cardAcceso(
              icono: Icons.pending_actions,
              color: Colors.orange,
              titulo: 'Órdenes pendientes de consumo',
              subtitulo: 'Declara los materiales de tus OTs completadas',
              contador: _pendientes,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      PendientesConsumoScreen(mes: _mes, anno: _anno),
                ),
              ).then((_) => _cargar()),
            ),
            const SizedBox(height: 12),
            _cardAcceso(
              icono: Icons.history,
              color: Colors.green,
              titulo: 'Historial de órdenes consumidas',
              subtitulo: 'Fecha de ejecución, de consumo y materiales',
              contador: _consumidas,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      HistorialConsumosScreen(mes: _mes, anno: _anno),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardAcceso({
    required IconData icono,
    required Color color,
    required String titulo,
    required String subtitulo,
    required int contador,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icono, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(subtitulo,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _cargando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      '$contador',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: color),
                    ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lista de OTs pendientes → selección de materiales → registro.
///
/// Réplica del flujo de agente_desconexiones, pero el stock viene de la API
/// traza materiales (vía proxy) y el registro va a `consumos_traza` (Supabase).
class PendientesConsumoScreen extends StatefulWidget {
  /// Mes y año a mostrar. Si no se indican, se usa el mes actual.
  final int? mes;
  final int? anno;

  const PendientesConsumoScreen({super.key, this.mes, this.anno});

  @override
  State<PendientesConsumoScreen> createState() =>
      _PendientesConsumoScreenState();
}

class _PendientesConsumoScreenState extends State<PendientesConsumoScreen> {
  final _service = TrazaConsumoService();

  bool _cargando = true;
  String? _error;
  String? _rut;
  List<OrdenPendienteConsumo> _ordenes = [];
  StockConsumoTecnico? _stock;

  late final int _mes = widget.mes ?? DateTime.now().month;
  late final int _anno = widget.anno ?? DateTime.now().year;

  static const _nombresMes = [
    '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

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

      final results = await Future.wait([
        _service.obtenerOrdenesPendientesMes(rut, mes: _mes, anno: _anno),
        _service.obtenerStock(rut),
      ]);

      if (!mounted) return;
      setState(() {
        _rut = rut;
        _ordenes = results[0] as List<OrdenPendienteConsumo>;
        _stock = results[1] as StockConsumoTecnico;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  void _abrirOrden(OrdenPendienteConsumo orden) {
    final stock = _stock;
    if (stock == null || _rut == null) return;

    // OT ya declarada pero sin confirmación de bodega → reenviar el traspaso
    // guardado (no se vuelve a seleccionar material).
    if (orden.traspasoPendiente) {
      _confirmarReenvio(orden);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SeleccionMaterialesScreen(
          orden: orden,
          rut: _rut!,
          stock: stock,
          service: _service,
          onConsumoOk: _cargar,
        ),
      ),
    );
  }

  Future<void> _confirmarReenvio(OrdenPendienteConsumo orden) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.sync_problem, color: Colors.red),
            SizedBox(width: 8),
            Expanded(
              child: Text('Consumo sin confirmar',
                  style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
        content: Text(
          'La OT ${orden.ordenTrabajo} ya tiene su consumo declarado, pero '
          'bodega (traza materiales) aún no confirma el descuento.\n\n'
          '¿Reenviar ahora?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('REENVIAR'),
          ),
        ],
      ),
    );
    if (confirmar != true || _rut == null || !mounted) return;

    setState(() => _cargando = true);
    final r = await _service.reenviarTraspaso(
      ordenTrabajo: orden.ordenTrabajo,
      rutTecnico: _rut!,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.confirmadoEnErp
          ? '✓ Consumo confirmado en bodega (${orden.ordenTrabajo})'
          : 'Bodega aún no confirma: ${r.mensaje}'),
      backgroundColor: r.confirmadoEnErp ? Colors.green : Colors.orange,
    ));
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pendientes · ${_nombresMes[_mes]}'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildLista(),
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
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLista() {
    final sinStock = _stock?.vacio ?? true;

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (sinStock)
            Card(
              color: Colors.orange[50],
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: Colors.orange),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sin inventario registrado para tu RUT en traza '
                        'materiales. Verifica con bodega.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_ordenes.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Column(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: Colors.green, size: 56),
                  SizedBox(height: 16),
                  Text(
                    'Sin órdenes pendientes',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'No tienes OTs completadas pendientes de declarar consumo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            )
          else
            ..._buildListaAgrupada(),
        ],
      ),
    );
  }

  /// Órdenes agrupadas por día (más reciente primero), con encabezado.
  List<Widget> _buildListaAgrupada() {
    final grupos = <String, List<OrdenPendienteConsumo>>{};
    for (final o in _ordenes) {
      grupos.putIfAbsent(o.fechaTrabajo, () => []).add(o);
    }

    final widgets = <Widget>[];
    for (final e in grupos.entries) {
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Row(
          children: [
            Text(
              _formatearDia(e.key),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${e.value.length}',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700]),
              ),
            ),
            const Expanded(child: Divider(indent: 10)),
          ],
        ),
      ));
      widgets.addAll(e.value.map(_buildCardOrden));
    }
    return widgets;
  }

  /// "2026-08-24" → "Lunes 24/08"
  String _formatearDia(String fecha) {
    const dias = ['', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes',
        'Sábado', 'Domingo'];
    try {
      final d = DateTime.parse(fecha);
      final dd = d.day.toString().padLeft(2, '0');
      final mm = d.month.toString().padLeft(2, '0');
      return '${dias[d.weekday]} $dd/$mm';
    } catch (_) {
      return fecha;
    }
  }

  Widget _buildCardOrden(OrdenPendienteConsumo orden) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () => _abrirOrden(orden),
        title: Text(
          orden.ordenTrabajo,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(orden.tipoActividad,
                style: TextStyle(color: Colors.blue[700], fontSize: 13)),
            if (orden.cliente.isNotEmpty && orden.cliente != 'Sin Datos')
              Text(orden.cliente, style: const TextStyle(fontSize: 12)),
            if (orden.direccionCompleta.isNotEmpty)
              Text(orden.direccionCompleta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 11, color: Colors.grey)),
            Text(orden.fechaTrabajo,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: (orden.traspasoPendiente ? Colors.red : Colors.orange)
                .withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            orden.traspasoPendiente ? 'REENVIAR' : 'PENDIENTE',
            style: TextStyle(
                color: orden.traspasoPendiente ? Colors.red : Colors.orange,
                fontSize: 10,
                fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

// ── Detalle: selección de materiales ─────────────────────────────────────────

class SeleccionMaterialesScreen extends StatefulWidget {
  final OrdenPendienteConsumo orden;
  final String rut;
  final StockConsumoTecnico stock;
  final TrazaConsumoService service;
  final VoidCallback onConsumoOk;

  const SeleccionMaterialesScreen({
    super.key,
    required this.orden,
    required this.rut,
    required this.stock,
    required this.service,
    required this.onConsumoOk,
  });

  @override
  State<SeleccionMaterialesScreen> createState() =>
      _SeleccionMaterialesScreenState();
}

class _SeleccionMaterialesScreenState extends State<SeleccionMaterialesScreen> {
  final _sabana = KeplerSabanaService();

  /// Cantidades elegidas por categoría (no seriados).
  final Map<String, int> _cantidades = {};

  /// Equipos seriados registrados en TOA (solo lectura, no editables).
  /// Vienen de la tabla histórica `equipos_seriados_traza`.
  List<EquipoInstaladoToa> _equiposToa = const [];
  bool _cargandoToa = true;

  bool _enviando = false;

  String get _tipoActividad => widget.orden.tipoActividad;

  @override
  void initState() {
    super.initState();
    _prefillMinimos();
    _cargarEquiposToa();
  }

  Future<void> _cargarEquiposToa() async {
    final equipos = await _sabana.equiposInstalados(widget.orden.ordenTrabajo);
    if (!mounted) return;
    setState(() {
      _equiposToa = equipos;
      _cargandoToa = false;
    });
  }

  void _prefillMinimos() {
    if (!consumoExigirMinimos(_tipoActividad)) return;
    for (final cat in _noSeriadasVisibles) {
      final min = consumoMinimo(cat.nombre, _tipoActividad) ?? 0;
      if (min <= 0) continue;
      final saldo = _saldo(cat.nombre);
      if (saldo <= 0) continue;
      _cantidades[cat.nombre] = min.clamp(0, saldo);
    }
  }

  int _saldo(String categoria) =>
      widget.stock.porCategoria[categoria] ?? 0;

  /// Categorías visibles: con saldo, o con mínimo obligatorio para
  /// esta actividad (aunque no haya saldo, para avisar).
  bool _visible(CategoriaMaterial cat) {
    if (_saldo(cat.nombre) > 0) return true;
    final min = consumoMinimo(cat.nombre, _tipoActividad) ?? 0;
    return min > 0;
  }

  List<CategoriaMaterial> get _noSeriadasVisibles => kCategoriasConsumo
      .where((c) => !c.esSeriado && _visible(c))
      .toList();

  int get _totalDrop {
    var total = 0;
    for (final cat in kConsumoCategoriasDrop) {
      total += _cantidades[cat] ?? 0;
    }
    return total;
  }

  String? get _dropSeleccionado {
    for (final cat in kConsumoCategoriasDrop) {
      if ((_cantidades[cat] ?? 0) > 0) return cat;
    }
    return null;
  }

  // ── Acciones ──

  Future<void> _ajustar(String categoria, int delta) async {
    final actual = _cantidades[categoria] ?? 0;
    final saldo = _saldo(categoria);
    final maxCat = consumoMaximo(categoria, _tipoActividad);

    if (delta > 0 && kConsumoCategoriasDrop.contains(categoria)) {
      final dropActual = _dropSeleccionado;
      if (dropActual != null &&
          dropActual != categoria &&
          _totalDrop >= kConsumoMaxDropTotal) {
        await _alerta('Solo se permite 1 drop por orden.\n'
            'Ya seleccionaste $dropActual.');
        return;
      }
    }

    var nuevo = actual + delta;
    if (nuevo < 0) nuevo = 0;
    if (nuevo > saldo) nuevo = saldo;
    if (maxCat != null && nuevo > maxCat) {
      await _alerta(
          'Esta actividad permite un máximo de $maxCat × $categoria.');
      nuevo = maxCat;
    }

    setState(() {
      if (nuevo == 0) {
        _cantidades.remove(categoria);
      } else {
        _cantidades[categoria] = nuevo;
      }
    });
  }

  Future<void> _alerta(String mensaje) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Límite de consumo', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Text(mensaje),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ACEPTAR'),
          ),
        ],
      ),
    );
  }

  Future<void> _enviar() async {
    final equiposToa = _equiposToa;

    if (_cantidades.isEmpty && equiposToa.isEmpty) {
      // Altas/Migraciones/Traslados exigen mínimos → nunca pueden ir vacías.
      if (consumoExigirMinimos(_tipoActividad)) {
        await _alerta('Selecciona al menos un material antes de registrar.');
        return;
      }
      // Reparaciones/Modificaciones: se permite DECLARACIÓN CERO
      // (trabajo sin consumo de materiales), con confirmación.
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFFC62828), // rojo alerta
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white, width: 2),
          ),
          title: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.white, size: 52),
              SizedBox(height: 10),
              Text(
                '¿REGISTRAR SIN CONSUMO?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'ComicNeue',
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          content: Text(
            'Vas a declarar la OT ${widget.orden.ordenTrabajo} '
            'SIN consumo de materiales (declaración cero).\n\n'
            '¿Confirmas que esta ${_tipoActividad.toLowerCase()} '
            'no utilizó materiales?',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'ComicNeue',
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'VOLVER',
                style: TextStyle(
                  fontFamily: 'ComicNeue',
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFFC62828),
              ),
              child: const Text(
                'SÍ, SIN CONSUMO',
                style: TextStyle(
                  fontFamily: 'ComicNeue',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
    }

    // Validación de materiales según la receta.
    final err = validarConsumoCantidades(
      tipoActividad: _tipoActividad,
      totalPorCategoria: Map.of(_cantidades),
    );
    if (err != null) {
      await _alerta(err);
      return;
    }

    // Corroborar mínimos de equipos contra lo cargado desde TOA
    // (ej: Alta/Migración exige mín 1 ONT registrada en la base).
    final equiposPorTipo = <String, int>{};
    for (final e in equiposToa) {
      equiposPorTipo[e.categoria] = (equiposPorTipo[e.categoria] ?? 0) + 1;
    }
    final errEquipos = validarEquiposToa(
      tipoActividad: _tipoActividad,
      equiposPorTipo: equiposPorTipo,
    );
    if (errEquipos != null) {
      await _alerta(errEquipos);
      return;
    }

    // La rebaja por categoría va al SKU con más saldo (misma mecánica que
    // agente_desconexiones): el técnico nunca elige marca.
    final noSeriados = <ItemStockConsumo>[];
    final cantidadesPorItem = <ItemStockConsumo, int>{};
    for (final e in _cantidades.entries) {
      final items = widget.stock.items
          .where((i) => !i.esSeriado && i.categoria == e.key)
          .toList()
        ..sort((a, b) => b.cantidad.compareTo(a.cantidad));
      if (items.isEmpty) continue;
      noSeriados.add(items.first);
      cantidadesPorItem[items.first] = e.value;
    }

    // SKU de cada serie TOA, resuelto desde el inventario actual (lo pide
    // el ERP para descontar el equipo).
    final skuPorSerie = <String, String>{
      for (final i in widget.stock.items)
        if (i.esSeriado && i.serie != null) i.serie!: i.sku,
    };

    setState(() => _enviando = true);
    final result = await widget.service.registrarConsumo(
      ordenTrabajo: widget.orden.ordenTrabajo,
      rutTecnico: widget.rut,
      tipoActividad: _tipoActividad,
      fechaTrabajo: widget.orden.fechaTrabajo,
      direccion: widget.orden.direccionCompleta,
      noSeriados: noSeriados,
      cantidades: cantidadesPorItem,
      equiposToa: equiposToa,
      skuPorSerie: skuPorSerie,
    );
    if (!mounted) return;
    setState(() => _enviando = false);

    if (result.exito) {
      widget.onConsumoOk();
      final confirmado = result.confirmadoEnErp;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                confirmado ? Icons.check_circle : Icons.schedule_send,
                color: confirmado ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  confirmado
                      ? 'Consumo confirmado'
                      : 'Consumo por confirmar',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: Text(
            result.traspasoEstado == 'sin_consumo'
                ? 'OT ${widget.orden.ordenTrabajo}\n'
                    'Declarada SIN consumo de materiales (declaración cero).'
                : confirmado
                    ? 'OT ${widget.orden.ordenTrabajo}\n'
                        'Materiales descontados en bodega (traza materiales).'
                        '${result.traspasoEstado == 'parcial' ? '\n\n⚠️ Algunas líneas quedaron en revisión de bodega.' : ''}'
                    : 'OT ${widget.orden.ordenTrabajo}\n'
                        'Tu declaración quedó guardada, pero bodega aún no '
                        'confirma el descuento. La orden seguirá visible como '
                        '"REENVIAR" hasta lograr la confirmación.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(
                backgroundColor: confirmado ? Colors.green : Colors.orange,
              ),
              child: const Text('ACEPTAR'),
            ),
          ],
        ),
      );
    } else {
      await _alerta('No se pudo registrar el consumo:\n${result.mensaje}');
    }
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final totalSeleccionado =
        _cantidades.values.fold<int>(0, (a, b) => a + b) + _equiposToa.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.orden.ordenTrabajo,
            style: const TextStyle(fontSize: 15)),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Tipificación precisa (ej: "Alta 2 Play") + dirección, centradas
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              children: [
                Text(
                  _tipoActividad,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    letterSpacing: 0.3,
                  ),
                ),
                if (widget.orden.direccionCompleta.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 14, color: Colors.grey),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            widget.orden.direccionCompleta,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_noSeriadasVisibles.isNotEmpty) ...[
                  const Text('MATERIALES',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey)),
                  const SizedBox(height: 8),
                  ..._noSeriadasVisibles.map(_filaNoSeriada),
                  const SizedBox(height: 16),
                ],
                const Text('EQUIPOS REGISTRADOS EN TOA',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
                const SizedBox(height: 8),
                _buildSeccionEquiposToa(),
                if (_noSeriadasVisibles.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No tienes materiales con saldo para esta actividad.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _enviando ? null : _enviar,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _enviando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check),
            label: Text(_enviando
                ? 'REGISTRANDO...'
                : 'REGISTRAR CONSUMO ($totalSeleccionado)'),
          ),
        ),
      ),
    );
  }

  Widget _filaNoSeriada(CategoriaMaterial cat) {
    final saldo = _saldo(cat.nombre);
    final cantidad = _cantidades[cat.nombre] ?? 0;
    final min = consumoMinimo(cat.nombre, _tipoActividad);
    final max = consumoMaximo(cat.nombre, _tipoActividad);
    final hint = [
      if (min != null) 'Mín $min',
      if (max != null) 'Máx $max',
    ].join(' · ');
    final sinSaldo = saldo <= 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cat.nombre,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    sinSaldo ? 'Sin saldo — avisa a bodega' : 'Saldo: $saldo'
                        '${hint.isNotEmpty ? '  ·  $hint' : ''}',
                    style: TextStyle(
                        fontSize: 11,
                        color: sinSaldo ? Colors.red : Colors.grey[600]),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed:
                  sinSaldo || cantidad == 0 ? null : () => _ajustar(cat.nombre, -1),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 32,
              child: Text(
                '$cantidad',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              onPressed: sinSaldo ? null : () => _ajustar(cat.nombre, 1),
              icon: const Icon(Icons.add_circle_outline),
              color: Colors.blue,
            ),
          ],
        ),
      ),
    );
  }

  /// Equipos seriados registrados por el técnico en TOA. Solo lectura:
  /// no se pueden agregar, quitar ni editar desde la app.
  Widget _buildSeccionEquiposToa() {
    if (_cargandoToa) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Consultando equipos registrados en TOA…',
                  style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final equipos = _equiposToa;

    if (equipos.isEmpty) {
      return Card(
        color: Colors.grey[100],
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.grey),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sin equipos seriados registrados para esta orden.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Agrupar por tipo, en orden fijo: ONT → Extensores → Decos → otros
    const ordenTipos = ['ONT', 'EXTENSOR', 'DECO', 'GATEWAY', 'MTA', 'OTRO'];
    const etiquetas = {
      'ONT': 'ONT',
      'EXTENSOR': 'EXTENSORES',
      'DECO': 'DECOS',
      'GATEWAY': 'GATEWAYS',
      'MTA': 'MTA',
      'OTRO': 'OTROS EQUIPOS',
    };

    final grupos = <String, List<EquipoInstaladoToa>>{};
    for (final e in equipos) {
      grupos.putIfAbsent(e.categoria, () => []).add(e);
    }
    final tiposPresentes = [
      ...ordenTipos.where(grupos.containsKey),
      ...grupos.keys.where((t) => !ordenTipos.contains(t)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final tipo in tiposPresentes) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Row(
              children: [
                Text(
                  etiquetas[tipo] ?? tipo,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: Colors.blue[700],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${grupos[tipo]!.length}',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700]),
                  ),
                ),
              ],
            ),
          ),
          ...grupos[tipo]!.map((e) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 9),
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code_2,
                          size: 18, color: Colors.blue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.serie,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                letterSpacing: 0.5,
                              ),
                            ),
                            if (e.descripcion.isNotEmpty &&
                                e.descripcion != e.categoria)
                              Text(
                                e.descripcion,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Text(
                          'TOA',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ],
    );
  }
}
