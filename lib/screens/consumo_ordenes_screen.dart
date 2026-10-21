import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/traza_consumo_service.dart';
import 'consumo_materiales_screen.dart';
import 'historial_consumos_screen.dart';

const _nombresMes = [
  '',
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

/// Menú de consumo de órdenes: mes anterior cerrado, mes en curso e historial.
class ConsumoOrdenesScreen extends StatefulWidget {
  final int? pendientesCerrado;
  final int? pendientesActual;

  const ConsumoOrdenesScreen({
    super.key,
    this.pendientesCerrado,
    this.pendientesActual,
  });

  @override
  State<ConsumoOrdenesScreen> createState() => _ConsumoOrdenesScreenState();
}

class _ConsumoOrdenesScreenState extends State<ConsumoOrdenesScreen> {
  final _service = TrazaConsumoService();

  late int? _pendCerrado = widget.pendientesCerrado;
  late int? _pendActual = widget.pendientesActual;
  bool _cargando = false;

  late final DateTime _now = DateTime.now();
  int get _mesActual => _now.month;
  int get _annoActual => _now.year;
  int get _mesCerrado => _now.month == 1 ? 12 : _now.month - 1;
  int get _annoCerrado => _now.month == 1 ? _now.year - 1 : _now.year;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final rut =
          prefs.getString('rut_tecnico') ?? prefs.getString('rut') ?? '';
      if (rut.isEmpty) return;
      final cerrado = await _service.contarPendientesMes(
        rut: rut,
        mes: _mesCerrado,
        anno: _annoCerrado,
      );
      final actual = await _service.contarPendientesMes(
        rut: rut,
        mes: _mesActual,
        anno: _annoActual,
      );
      if (!mounted) return;
      setState(() {
        _pendCerrado = cerrado;
        _pendActual = actual;
      });
    } catch (e) {
      debugPrint('[ConsumoOrdenes] error cargando pendientes: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _abrirMes(int mes, int anno) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConsumoMaterialesScreen(mes: mes, anno: anno),
      ),
    );
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      appBar: AppBar(
        title: const Text('Consumo Órdenes'),
        backgroundColor: const Color(0xFF0A1628),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _cardMes(
              titulo: '${_nombresMes[_mesCerrado]} $_annoCerrado',
              etiqueta: 'MES ANTERIOR · CERRADO',
              icono: Icons.lock_outline,
              pendientes: _pendCerrado,
              colores: const [Color(0xFF475569), Color(0xFF1E293B)],
              onTap: () => _abrirMes(_mesCerrado, _annoCerrado),
            ),
            const SizedBox(height: 14),
            _cardMes(
              titulo: '${_nombresMes[_mesActual]} $_annoActual',
              etiqueta: 'MES EN CURSO',
              icono: Icons.hourglass_bottom,
              pendientes: _pendActual,
              colores: const [Color(0xFF16A34A), Color(0xFF0B7A55)],
              onTap: () => _abrirMes(_mesActual, _annoActual),
            ),
            const SizedBox(height: 14),
            _cardHistorial(),
          ],
        ),
      ),
    );
  }

  Widget _cardMes({
    required String titulo,
    required String etiqueta,
    required IconData icono,
    required int? pendientes,
    required List<Color> colores,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colores),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: colores.first.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icono, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      etiqueta,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      pendientes == null
                          ? 'Calculando pendientes…'
                          : pendientes == 0
                          ? 'Sin órdenes pendientes de consumo'
                          : '$pendientes ${pendientes == 1 ? 'orden pendiente' : 'órdenes pendientes'} de consumo',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Text(
                    pendientes == null ? '…' : '$pendientes',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white70),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardHistorial() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                HistorialConsumosScreen(mes: _mesActual, anno: _annoActual),
          ),
        ),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.history,
                  color: Color(0xFF3B82F6),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HISTORIAL',
                      style: TextStyle(
                        color: Color(0xFF3B82F6),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Órdenes consumidas',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Por mes y por fecha de ejecución, con materiales y equipos',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}
