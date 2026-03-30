import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tag_service.dart';
import '../services/produccion_service.dart';
import '../services/calidad_traza_service.dart';
import '../services/reversa_service.dart';
import '../services/krp_consumo_service.dart';
import '../widgets/creaciones_loading.dart';
import 'detalle_tag_screen.dart';
import 'calidad_screen.dart';
import 'calidad_detalle_screen.dart';
import 'produccion_screen.dart';
import 'consumo_screen.dart';
import 'reversa_screen.dart';
import 'configuracion_screen.dart';

class TuMesScreen extends StatefulWidget {
  const TuMesScreen({super.key});

  @override
  State<TuMesScreen> createState() => _TuMesScreenState();
}

class _TuMesScreenState extends State<TuMesScreen> {
  final TagService _tagService = TagService();
  final ProduccionService _produccionService = ProduccionService();
  final CalidadTrazaService _calidadService = CalidadTrazaService();
  // final KrpConsumoService _consumoService = KrpConsumoService(); // PAUSADO

  int _totalTag = 0;
  int _cantidadPasos = 0;
  int _equiposPendientes = 0;
  int _equiposPendientesReversa = 0;
  double _promedioRGU = 0.0;
  
  // Calidad - períodos
  Map<String, dynamic>? _calidadCerrado;   // Periodo cerrado (a pago)
  Map<String, dynamic>? _calidadActual;
  Map<String, dynamic>? _calidadAnterior;
  String _periodoCerrado = '';
  String _periodoActual = '';
  String _periodoAnterior = '';
  String _tipoContratoCalidad = 'nuevo'; // 'nuevo' o 'antiguo' - para desglose por tecnología
  
  // Producción - períodos
  Map<String, dynamic>? _produccionCerrado;   // Mes - 1 (cerrado) = febrero
  Map<String, dynamic>? _produccionActual;    // Mes 0 (en curso)  = marzo
  
  // Consumo - períodos
  Map<String, dynamic>? _consumoCerrado;   // Mes anterior cerrado
  Map<String, dynamic>? _consumoActual;    // Mes actual en curso
  
  // Reversa - períodos
  Map<String, dynamic>? _reversaCerrado;   // Mes anterior cerrado
  Map<String, dynamic>? _reversaActual;    // Mes actual en curso
  
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _periodoCerrado = _calidadService.getPeriodoMidiendo();
    _periodoActual = _calidadService.getPeriodoProximo();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);

    _totalTag = await _tagService.getTotalMesActual();
    _cantidadPasos = await _tagService.getCantidadPasosMes();

    // Cargar equipos pendientes de reversa
    try {
      final prefs = await SharedPreferences.getInstance();
      final rut = prefs.getString('rut_tecnico');
      if (rut != null) {
        final pendientes = await Supabase.instance.client
            .from('desinstalaciones_crea')
            .select('id')
            .eq('rut_tecnico', rut)
            .inFilter('estado', ['pendiente_entrega', 'rechazado', 'en_revision']);
        _equiposPendientes = pendientes.length;
      } else {
        _equiposPendientes = 0;
      }
    } catch (e) {
      print('⚠️ [TuMes] Error cargando equipos pendientes: $e');
      _equiposPendientes = 0;
    }

    // Cargar equipos pendientes para el card de Reversa
    await _cargarEquiposPendientes();

    // Cargar promedio RGU del mes actual
    await _cargarPromedioRGU();

    // Cargar porcentaje de reiteración (calidad)
    await _cargarReiteracionCalidad();

    // Cargar estadísticas de consumo
    await _cargarEstadisticasConsumo();

    setState(() => _cargando = false);
  }

  Future<void> _cargarPromedioRGU() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rutTecnico = prefs.getString('rut_tecnico');
      
      if (rutTecnico != null) {
        final now = DateTime.now();
        
        // Mes -1 (CERRADO): febrero si estamos en marzo
        final mesCerrado = now.month - 1 < 1 ? 12 : now.month - 1;
        final annoCerrado = now.month - 1 < 1 ? now.year - 1 : now.year;
        
        // Mes 0 (EN CURSO): marzo
        final mesActual = now.month;
        final annoActual = now.year;
        
        final resultados = await Future.wait([
          _produccionService.obtenerResumenMesRGU(
            rutTecnico,
            mes: mesActual,
            anno: annoActual,
          ),
          _produccionService.obtenerResumenMesRGU(
            rutTecnico,
            mes: mesCerrado,
            anno: annoCerrado,
          ),
        ]);

        setState(() {
          _produccionActual = resultados[0];
          _produccionCerrado = resultados[1];
          _promedioRGU = (resultados[0]['promedioRGU'] as num?)?.toDouble() ?? 0.0;
        });
      } else {
        setState(() {
          _produccionActual = null;
          _produccionCerrado = null;
          _promedioRGU = 0.0;
        });
      }
    } catch (e) {
      print('⚠️ [TuMes] Error cargando promedio RGU: $e');
      setState(() {
        _produccionActual = null;
        _produccionCerrado = null;
        _promedioRGU = 0.0;
      });
    }
  }

  Future<void> _cargarEquiposPendientes() async {
    final prefs = await SharedPreferences.getInstance();
    final rutTecnico = prefs.getString('rut_tecnico');
    if (rutTecnico == null) {
      setState(() {
        _equiposPendientesReversa = 0;
        _reversaCerrado = null;
        _reversaActual = null;
      });
      return;
    }

    try {
      // Usar el mismo servicio que reversa_screen.dart
      final reversaService = ReversaService();
      final now = DateTime.now();
      
      // Mes anterior cerrado
      final mesCerrado = now.month - 1 < 1 ? 12 : now.month - 1;
      final annoCerrado = now.month - 1 < 1 ? now.year - 1 : now.year;
      
      // Mes actual en curso
      final mesActual = now.month;
      final annoActual = now.year;
      
      final resumenCerrado = await reversaService.obtenerResumenReversaMes(
        rutTecnico,
        mes: mesCerrado,
        anno: annoCerrado,
      );
      
      final resumenActual = await reversaService.obtenerResumenReversaMes(
        rutTecnico,
        mes: mesActual,
        anno: annoActual,
      );

      // Calcular equipos pendientes del mes actual
      final totalEquipos = (resumenActual['totalEquipos'] ?? 0) as int;
      final recibidos = (resumenActual['recibidos'] ?? 0) as int;
      final equiposPendientes = totalEquipos - recibidos;

      print('📦 [TuMes] Equipos pendientes reversa: $equiposPendientes (Total:$totalEquipos, Recibidos:$recibidos)');

      setState(() {
        _reversaCerrado = resumenCerrado;
        _reversaActual = resumenActual;
        _equiposPendientesReversa = equiposPendientes;
      });
    } catch (e) {
      print('⚠️ [TuMes] Error cargando equipos pendientes reversa: $e');
      setState(() {
        _reversaCerrado = null;
        _reversaActual = null;
        _equiposPendientesReversa = 0;
      });
    }
  }

  Future<void> _cargarReiteracionCalidad() async {
    final prefs = await SharedPreferences.getInstance();
    final rutTecnico = prefs.getString('rut_tecnico');
    final periodoBonoMarzo = _calidadService.getPeriodoMidiendo();
    final periodoBonoAbril = _calidadService.getPeriodoProximo();

    if (rutTecnico == null) {
      setState(() {
        _calidadCerrado = null;
        _calidadActual = null;
        _calidadAnterior = null;
        _periodoCerrado = '';
        _periodoActual = '';
        _periodoAnterior = '';
      });
      return;
    }

    try {
      final tipoContrato =
          await _calidadService.obtenerTipoContrato(rutTecnico, prefs: prefs);
      print(
          '📋 [TuMes] Calidad tipo=$tipoContrato períodos $periodoBonoMarzo | $periodoBonoAbril');

      List<Map<String, dynamic>?> resultados;
      if (tipoContrato == 'antiguo') {
        resultados = await Future.wait([
          _calidadService.obtenerCalidadPorPeriodoPorTecnologia(
              rutTecnico, periodoBonoMarzo),
          _calidadService.obtenerCalidadPorPeriodoPorTecnologia(
              rutTecnico, periodoBonoAbril),
        ]);
      } else {
        resultados = await Future.wait([
          _calidadService.obtenerCalidadPorPeriodo(rutTecnico, periodoBonoMarzo),
          _calidadService.obtenerCalidadPorPeriodo(rutTecnico, periodoBonoAbril),
        ]);
      }

      setState(() {
        _tipoContratoCalidad = tipoContrato;
        _calidadCerrado = resultados[0];
        _calidadActual = resultados[1];
        _calidadAnterior = null;
        _periodoCerrado = periodoBonoMarzo;
        _periodoActual = periodoBonoAbril;
        _periodoAnterior = '';
      });
    } catch (e) {
      print('⚠️ [TuMes] Error cargando calidad: $e');
      final tipoFallback =
          await _calidadService.obtenerTipoContrato(rutTecnico, prefs: prefs);
      setState(() {
        _tipoContratoCalidad = tipoFallback;
        _calidadCerrado = null;
        _calidadActual = null;
        _calidadAnterior = null;
        _periodoCerrado = periodoBonoMarzo;
        _periodoActual = periodoBonoAbril;
        _periodoAnterior = '';
      });
    }
  }

  Future<void> _cargarEstadisticasConsumo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rutTecnico = prefs.getString('rut_tecnico');
      
      if (rutTecnico != null) {
        final now = DateTime.now();
        
        // Mes anterior cerrado
        final mesCerrado = now.month - 1 < 1 ? 12 : now.month - 1;
        final annoCerrado = now.month - 1 < 1 ? now.year - 1 : now.year;
        
        // Mes actual en curso
        final mesActual = now.month;
        final annoActual = now.year;
        
        // CONSUMO PAUSADO - valores por defecto
        final estadisticasCerrado = {'totalPendientes': 0, 'detalles': {}};
        final estadisticasActual = {'totalPendientes': 0, 'detalles': {}};
        
        // final estadisticasCerrado = await _consumoService.obtenerEstadisticasMes(
        //   rutTecnico: rutTecnico,
        //   mes: mesCerrado,
        //   anno: annoCerrado,
        // );
        // 
        // final estadisticasActual = await _consumoService.obtenerEstadisticasMes(
        //   rutTecnico: rutTecnico,
        //   mes: mesActual,
        //   anno: annoActual,
        // );
        
        setState(() {
          _consumoCerrado = estadisticasCerrado;
          _consumoActual = estadisticasActual;
        });
      } else {
        setState(() {
          _consumoCerrado = null;
          _consumoActual = null;
        });
      }
    } catch (e) {
      print('⚠️ [TuMes] Error cargando consumo: $e');
      setState(() {
        _consumoCerrado = null;
        _consumoActual = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nombreMes = _getNombreMes(now.month);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tu Mes'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ConfiguracionScreen(),
              ),
            ),
            tooltip: 'Configuración',
          ),
        ],
      ),
      body: _cargando
          ? const CreacionesLoading(
              mensaje: 'Cargando tu resumen del mes...',
            )
          : RefreshIndicator(
              onRefresh: _cargarDatos,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título del mes + badge tipo contrato (CN/CA)
                    Row(
                      children: [
                        Text(
                          '$nombreMes ${now.year}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _tipoContratoCalidad == 'antiguo'
                                ? Colors.amber.withOpacity(0.3)
                                : Colors.blue.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _tipoContratoCalidad == 'antiguo'
                                  ? Colors.amber
                                  : Colors.blue,
                            ),
                          ),
                          child: Text(
                            _tipoContratoCalidad == 'antiguo' ? 'CA' : 'CN',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _tipoContratoCalidad == 'antiguo'
                                  ? Colors.amber[700]
                                  : Colors.blue[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Card TAG
                    _buildMenuCard(
                      icon: Icons.local_offer,
                      color: Colors.indigo,
                      titulo: 'Gasto TAG',
                      valor: '\$${_formatearNumero(_totalTag)}',
                      subtitulo: '$_cantidadPasos pórticos este mes',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DetalleTagScreen()),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Card Calidad
                    _buildCardCalidadCompleto(),

                    const SizedBox(height: 12),

                    // Card Producción completo con dos períodos
                    _buildCardProduccionCompleto(),

                    const SizedBox(height: 12),

                    // Card Consumo completo con dos períodos
                    _buildCardConsumoCompleto(),

                    const SizedBox(height: 12),

                    // Card Reversa completo con dos períodos
                    _buildCardReversaCompleto(),
                  ],
                ),
              ),
            ),
    );
  }

  /// Widget para mostrar el card de calidad completo con dos períodos
  Widget _buildCardCalidadCompleto() {
    final now = DateTime.now();
    
    // Período cerrado — parear con Producción: usar ordenesCompletadas de produccion como denominador
    final reiteradosCerrado = (_calidadCerrado?['total_reiterados'] as num?)?.toInt() ?? 0;
    final completadasCerrado = (_produccionCerrado?['ordenesCompletadas'] as num?)?.toInt() ??
        (_calidadCerrado?['total_completadas'] as num?)?.toInt() ?? 0;
    final porcentajeCerrado = completadasCerrado > 0
        ? reiteradosCerrado / completadasCerrado * 100
        : (_calidadCerrado?['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;
    final periodoCerrado =
        _calidadCerrado?['periodo']?.toString() ?? _periodoCerrado;
    
    // Formato período: MM-YYYY (ej: "02-2026")
    String nombreMesCerrado = '';
    int mesGarantiaCerrado = now.month - 1;
    if (periodoCerrado.isNotEmpty) {
      nombreMesCerrado = _calidadService.getNombreBono(periodoCerrado);
      final m = _calidadService.getMesMedicion(periodoCerrado);
      if (m >= 1 && m <= 12) mesGarantiaCerrado = m;
    }

    Color colorCerrado = _getColorCalidad(porcentajeCerrado);

    // Período actual (midiendo) — parear con Producción: usar ordenesCompletadas de produccion como denominador
    final reiteradosActual = (_calidadActual?['total_reiterados'] as num?)?.toInt() ?? 0;
    final completadasActual = (_produccionActual?['ordenesCompletadas'] as num?)?.toInt() ??
        (_calidadActual?['total_completadas'] as num?)?.toInt() ?? 0;
    final porcentajeActual = completadasActual > 0
        ? reiteradosActual / completadasActual * 100
        : (_calidadActual?['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;
    final periodoActual = _calidadActual?['periodo']?.toString() ?? _periodoActual;

    String nombreMesActual = '';
    int mesGarantiaActual = now.month;
    if (periodoActual.isNotEmpty) {
      nombreMesActual = _calidadService.getNombreBono(periodoActual);
      final m = _calidadService.getMesMedicion(periodoActual);
      if (m >= 1 && m <= 12) mesGarantiaActual = m;
    }

    Color colorActual = _getColorCalidad(porcentajeActual);

    // Días restantes hasta el último día del mes del período actual (fin de garantía)
    int mesCierre = now.month;
    int annoCierre = now.year;
    if (periodoActual.isNotEmpty) {
      final pa = _calidadService.parseMesAnnoMedicion(periodoActual);
      if (pa.$1 >= 1 && pa.$1 <= 12 && pa.$2 > 2000) {
        mesCierre = pa.$1;
        annoCierre = pa.$2;
      }
    }
    // Último día del mes de cierre
    final fechaCierre = DateTime(annoCierre, mesCierre + 1, 0);
    final diasRestantes = fechaCierre.difference(now).inDays;
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header centrado
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, color: Colors.amber),
                  const SizedBox(width: 8),
                  const Text(
                    'Calidad',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (_periodoCerrado.isNotEmpty || _periodoActual.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Chip(
                    avatar: Icon(
                      _tipoContratoCalidad == 'antiguo'
                          ? Icons.hub_outlined
                          : Icons.merge_type,
                      size: 18,
                      color: _tipoContratoCalidad == 'antiguo'
                          ? Colors.orange[200]
                          : Colors.lightBlue[200],
                    ),
                    label: Text(
                      _tipoContratoCalidad == 'antiguo'
                          ? 'Contrato antiguo · por tecnología'
                          : 'Contrato nuevo · consolidado',
                      style: const TextStyle(fontSize: 11),
                    ),
                    backgroundColor: Colors.grey[800],
                    side: BorderSide(
                      color: _tipoContratoCalidad == 'antiguo'
                          ? Colors.orange.withOpacity(0.5)
                          : Colors.cyan.withOpacity(0.5),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  Chip(
                    label: Text(
                      'Medición: $_periodoCerrado · $_periodoActual',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[400],
                      ),
                    ),
                    backgroundColor: Colors.grey[850],
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            
            // Dos columnas para los períodos
            IntrinsicHeight(
              child: Row(
                children: [
                  // IZQUIERDA: Período CERRADO
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CalidadDetalleScreen()),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[850],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Título - Bono Marzo
                            Row(
                              children: [
                                const Icon(Icons.hourglass_empty, size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'BONO ${nombreMesCerrado.toUpperCase()}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '1/${_getMesAbrev(mesGarantiaCerrado)} - fin/${_getMesAbrev(mesGarantiaCerrado)}',
                              style: const TextStyle(fontSize: 9, color: Colors.white70),
                            ),
                            const SizedBox(height: 8),
                            // Contenido: total o desglose por tecnología (completadas pareadas con Producción)
                            ..._buildContenidoCalidadPeriodo(
                              _calidadCerrado,
                              colorCerrado,
                              esContratoAntiguo: _tipoContratoCalidad == 'antiguo',
                              completadasOverride: completadasCerrado,
                            ),
                            if (_calidadCerrado == null)
                              Text(
                                'Sin datos de calidad',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            const SizedBox(height: 8),
                            // Estado
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey[700],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Midiendo',
                                style: TextStyle(fontSize: 9, color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // DERECHA: Bono Abril
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CalidadDetalleScreen()),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          border: Border.all(color: Colors.green, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Título - Bono Abril
                            Row(
                              children: [
                                const Icon(Icons.schedule, size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'BONO ${nombreMesActual.toUpperCase()}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                      ),
                    ),
                  ],
                ),
                            const SizedBox(height: 4),
                            Text(
                              '1/${_getMesAbrev(mesGarantiaActual)} - fin/${_getMesAbrev(mesGarantiaActual)}',
                              style: const TextStyle(fontSize: 9, color: Colors.white70),
                            ),
                            const SizedBox(height: 8),
                            // Contenido: total o desglose por tecnología (completadas pareadas con Producción)
                            ..._buildContenidoCalidadPeriodo(
                              _calidadActual,
                              colorActual,
                              esContratoAntiguo: _tipoContratoCalidad == 'antiguo',
                              completadasOverride: completadasActual,
                            ),
                            if (_calidadActual == null)
                              Text(
                                'Sin datos de calidad',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            const SizedBox(height: 8),
                            // Estado - Bono Abril (próximo)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Próximo',
                                style: TextStyle(fontSize: 9, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
              ),
            ),
    );
  }
  
  Color _getColorCalidad(double porcentaje) {
    if (porcentaje <= 3.0) {
      return Colors.green;
    } else if (porcentaje <= 6.0) {
      return Colors.lightGreen;
    } else if (porcentaje <= 10.0) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  /// Contenido del período de calidad: total (contrato nuevo) o desglose por tecnología (contrato antiguo).
  /// completadasOverride: ordenesCompletadas de Producción para parear denominador (ej: 2/89).
  List<Widget> _buildContenidoCalidadPeriodo(
    Map<String, dynamic>? calidad,
    Color colorBase, {
    required bool esContratoAntiguo,
    int? completadasOverride,
  }) {
    if (calidad == null) return [];

    if (!esContratoAntiguo) {
      final reit = (calidad['total_reiterados'] as num?)?.toInt() ?? 0;
      final comp = completadasOverride ?? (calidad['total_completadas'] as num?)?.toInt() ?? 0;
      final pct = comp > 0 ? reit / comp * 100 : (calidad['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;
      return [
        Text(
          '${pct.toStringAsFixed(1)}%',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorBase),
        ),
        Text(
          '$reit / $comp',
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
      ];
    }

    final porTec = (calidad['por_tecnologia'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (porTec.isEmpty) {
      final reit = (calidad['total_reiterados'] as num?)?.toInt() ?? 0;
      final comp = completadasOverride ?? (calidad['total_completadas'] as num?)?.toInt() ?? 0;
      final pct = comp > 0 ? reit / comp * 100 : (calidad['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;
      return [
        Text(
          '${pct.toStringAsFixed(1)}%',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorBase),
        ),
        Text('$reit / $comp', style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ];
    }

    final coloresTec = {
      'HFC': Colors.orange,
      'FTTH': Colors.purple,
      'RED_NEUTRA': Colors.cyan,
    };

    // Contrato antiguo con por_tecnologia: usar completadasOverride cuando hay una sola tech (solo HFC)
    return [
      ...porTec.map((t) {
        final tec = t['tecnologia']?.toString() ?? '';
        final reit = (t['reiterados'] as num?)?.toInt() ?? 0;
        final compOrig = (t['completadas'] as num?)?.toInt() ?? 0;
        final comp = (porTec.length == 1 && completadasOverride != null) ? completadasOverride : compOrig;
        final pct = comp > 0 ? reit / comp * 100 : (t['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;
        final color = coloresTec[tec] ?? colorBase;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(tec, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${pct.toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
                  ),
                ],
              ),
              Text('$reit / $comp', style: const TextStyle(fontSize: 10, color: Colors.white70)),
            ],
          ),
        );
      }),
    ];
  }

  Widget _buildMenuCard({
    required IconData icon,
    required Color color,
    required String titulo,
    required String valor,
    required String subtitulo,
    Color? subtituloColor,
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      valor,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        fontSize: 12,
                        color: subtituloColor ?? Colors.grey[500],
                        fontWeight: subtituloColor != null ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCardReversa({
    required IconData icon,
    required Color color,
    required String titulo,
    required int equiposPendientes,
    required VoidCallback onTap,
  }) {
    final tienePendientes = equiposPendientes > 0;
    final colorValor = tienePendientes ? Colors.orange : Colors.green;
    
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      equiposPendientes.toString(),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: colorValor,
                      ),
                    ),
                    Text(
                      tienePendientes ? 'equipos pendientes' : 'Sin pendientes',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorValor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  String _formatearNumero(int numero) {
    return numero.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }


  String _getNombreMes(int mes) {
    const meses = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
                   'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    return meses[mes];
  }

  String _getNombreBonoPeriodo() {
    final ahora = DateTime.now();
    final mesActual = ahora.month;
    // El bono actual es del mes siguiente al de garantía
    final nombreBono = _getNombreBonoMes(mesActual + 1, ahora.year);
    return nombreBono;
  }

  String _getNombreBonoPago() {
    // El bono a pago es el del mes en curso
    // Ej: Si estamos en Diciembre 26, el bono a pago es DICIEMBRE (21 oct - 20 nov)
    final ahora = DateTime.now();
    final mesActual = ahora.month;
    final nombreBono = _getNombreBonoMes(mesActual, ahora.year);
    return nombreBono;
  }


  Color _getColorPosicionCalidad(int posicion) {
    if (posicion == 0) return Colors.grey;
    if (posicion == 1) return Colors.amber[700]!;  // Oro
    if (posicion == 2) return Colors.grey[400]!;   // Plata
    if (posicion == 3) return Colors.orange[700]!; // Bronce
    if (posicion <= 10) return Colors.green[700]!; // Top 10
    if (posicion <= 20) return Colors.blue[700]!;  // Top 20
    return Colors.grey[600]!;
  }

  IconData _getIconoPosicion(int posicion) {
    if (posicion <= 3) return Icons.emoji_events; // Trofeo
    if (posicion <= 10) return Icons.star;        // Estrella
    return Icons.person;                           // Persona
  }

  String _getNombreMesCorto(String periodo) {
    try {
      final partes = periodo.split('-');
      if (partes.length == 2) {
        final mes = int.tryParse(partes[1]) ?? 0;
        const meses = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
        if (mes >= 1 && mes <= 12) {
          return meses[mes];
        }
      }
    } catch (e) {
      // Ignorar errores
    }
    return '';
  }

  String _getNombreMesDesdePeriodo(String periodo) {
    try {
      final partes = periodo.split('-');
      if (partes.length == 2) {
        final mes = int.tryParse(partes[1]) ?? 0;
        // El período YA representa el mes del bono
        // Período 2025-11 → BONO NOV
        return _getNombreMes(mes);
      }
    } catch (e) {
      // Ignorar errores
    }
    return '';
  }

  Widget _buildMenuCardCalidad({
    required IconData icon,
    required Map<String, dynamic>? calidadActual,
    required Map<String, dynamic>? calidadAnterior,
    required String periodoActual,
    required String periodoAnterior,
  }) {
    // Calcular porcentajes y datos
    final porcentajeActual = (calidadActual?['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;
    final totalReiteradosActual = (calidadActual?['total_reiterados'] as num?)?.toInt() ?? 0;
    final totalCompletadasActual = (calidadActual?['total_completadas'] as num?)?.toInt() ?? 0;
    
    final porcentajeAnterior = (calidadAnterior?['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;
    final totalReiteradosAnterior = (calidadAnterior?['total_reiterados'] as num?)?.toInt() ?? 0;
    final totalCompletadasAnterior = (calidadAnterior?['total_completadas'] as num?)?.toInt() ?? 0;
    
    // Calcular períodos de trabajo y garantía
    final ahora = DateTime.now();
    final mesActualNum = ahora.month;
    final annoActual = ahora.year;
    
    // BONO ANTERIOR: Si hoy es dic 26, el bono anterior es DICIEMBRE (21 oct - 20 nov, garantía hasta 20 dic)
    // El nombre del bono es el mes de cierre de garantía + 1
    final nombreBonoAnterior = _getNombreBonoMes(mesActualNum, annoActual);
    final periodoTrabajoAnterior = _getPeriodoTrabajo(mesActualNum - 1, annoActual);
    final mesGarantiaAnterior = _getMesAbrev(mesActualNum);
    final cerradoAnterior = ahora.day > 20;
    final diasRestantesAnterior = cerradoAnterior ? 0 : (20 - ahora.day);
    
    // BONO ACTUAL: Si hoy es dic 26, el bono actual es ENERO (21 nov - 20 dic, garantía hasta 20 ene)
    final nombreBonoActual = _getNombreBonoMes(mesActualNum + 1, annoActual);
    final periodoTrabajoActual = _getPeriodoTrabajo(mesActualNum, annoActual);
    final mesGarantiaActual = _getMesAbrev(mesActualNum + 1);
    final cerradoActual = false;
    final diasRestantesActual = ahora.day <= 20 
        ? (20 - ahora.day) 
        : (DateTime(annoActual, mesActualNum + 1, 20).difference(ahora).inDays);
    
    final colorActual = _getColorCalidad(porcentajeActual);
    final colorAnterior = _getColorCalidad(porcentajeAnterior);
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header centrado
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.star, color: Colors.amber, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Calidad',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Dos bonos lado a lado (uniformes)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                // BONO ANTERIOR (cerrado)
                Expanded(
                  child: _buildBonoCard(
                    titulo: cerradoAnterior ? '🔒 $nombreBonoAnterior' : '⏳ $nombreBonoAnterior',
                    subtitulo: cerradoAnterior ? '(cerrado)' : '(midiendo)',
                    periodoTrabajo: periodoTrabajoAnterior,
                    mesGarantia: mesGarantiaAnterior,
                    porcentaje: porcentajeAnterior,
                    reiterados: totalReiteradosAnterior,
                    completadas: totalCompletadasAnterior,
                    color: colorAnterior,
                    diasRestantes: cerradoAnterior ? null : diasRestantesAnterior,
                    onTap: () => _mostrarDetalleCalidad(context, calidadAnterior, periodoAnterior),
                  ),
                ),
                const SizedBox(width: 10),
                
                // BONO ACTUAL (midiendo)
                Expanded(
                  child: _buildBonoCard(
                    titulo: '⏳ $nombreBonoActual',
                    subtitulo: '(midiendo)',
                    periodoTrabajo: periodoTrabajoActual,
                    mesGarantia: mesGarantiaActual,
                    porcentaje: porcentajeActual,
                    reiterados: totalReiteradosActual,
                    completadas: totalCompletadasActual,
                    color: colorActual,
                    diasRestantes: diasRestantesActual,
                    onTap: () => _mostrarDetalleCalidad(context, calidadActual, periodoActual),
                  ),
                ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildBonoCard({
    required String titulo,
    required String subtitulo,
    required String periodoTrabajo,
    required String mesGarantia,
    required double porcentaje,
    required int reiterados,
    required int completadas,
    required Color color,
    required int? diasRestantes,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Título con emoji
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              subtitulo,
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            
            // Período de trabajo
            Text(
              periodoTrabajo,
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            
            // Último día garantía
            Text(
              'Última garantía\n20 de $mesGarantia',
              style: TextStyle(
                fontSize: 8,
                color: Colors.grey[600],
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            
            // Porcentaje y números
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: [
                  Text(
                    '${porcentaje.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$reiterados / $completadas',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            
            // Días restantes (solo si está activo)
            if (diasRestantes != null) ...[
              const SizedBox(height: 8),
              Text(
                'Cierra en $diasRestantes días',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getNombreBonoMes(int mes, int anno) {
    // Ajustar si el mes es > 12 o < 1
    int mesAjustado = mes;
    if (mes > 12) mesAjustado = mes - 12;
    if (mes < 1) mesAjustado = 12 + mes;
    
    const meses = ['', 'ENE', 'FEB', 'MAR', 'ABR', 
                   'MAY', 'JUN', 'JUL', 'AGO',
                   'SEP', 'OCT', 'NOV', 'DIC'];
    return mesAjustado >= 1 && mesAjustado <= 12 ? 'BONO ${meses[mesAjustado]}' : 'BONO';
  }

  String _getPeriodoTrabajo(int mes, int anno) {
    // El período de trabajo es del 21 del mes (periodo-2) al 20 del mes (periodo-1)
    // Ejemplo: período 2025-11 (BONO NOV) → trabajo 21 SEP - 20 OCT
    int mesInicio = mes - 2;
    if (mesInicio < 1) mesInicio = 12 + mesInicio;
    
    int mesFin = mes - 1;
    if (mesFin < 1) mesFin = 12;
    
    final mesAbrevInicio = _getMesAbrev(mesInicio);
    final mesAbrevFin = _getMesAbrev(mesFin);
    
    return '21/$mesAbrevInicio - 20/$mesAbrevFin';
  }

  String _getMesAbrev(int mes) {
    // Ajustar si el mes es > 12 o < 1
    int mesAjustado = mes;
    if (mes > 12) mesAjustado = mes - 12;
    if (mes < 1) mesAjustado = 12 + mes;
    
    const meses = ['', 'ene', 'feb', 'mar', 'abr', 'may', 'jun', 
                   'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return mesAjustado >= 1 && mesAjustado <= 12 ? meses[mesAjustado] : '';
  }

  /// Widget para mostrar el card de producción completo con DOS períodos
  Widget _buildCardProduccionCompleto() {
    final now = DateTime.now();
    final mesActual  = now.month;
    final annoActual = now.year;
    final mesCerrado = mesActual - 1 < 1 ? 12 : mesActual - 1;
    final annoCerrado = mesActual - 1 < 1 ? annoActual - 1 : annoActual;

    // BONO ABR (trabajo de marzo — EN CURSO)
    final rguActual   = (_produccionActual?['promedioRGU'] as num?)?.toDouble() ?? 0.0;
    final totalActual = (_produccionActual?['totalRGU'] as num?)?.toDouble() ?? 0.0;
    final ordActual   = (_produccionActual?['ordenesCompletadas'] as num?)?.toInt() ?? 0;
    final diasActual  = (_produccionActual?['diasConProduccion'] as num?)?.toInt() ?? 0;
    final ptosActual  = (_produccionActual?['ptosHfc'] as num?)?.toDouble() ?? 0.0;
    final rguFtthActual = (_produccionActual?['rguFtth'] as num?)?.toDouble() ?? 0.0;
    final rguNeutraActual = (_produccionActual?['rguRedNeutra'] as num?)?.toDouble() ?? 0.0;
    final tipoContratoActual = _produccionActual?['tipoContrato']?.toString() ?? 'nuevo';
    final promedioPtsActual = (_produccionActual?['promedioPts'] as num?)?.toDouble() ?? 0.0;
    final mesBono     = mesActual == 12 ? 1 : mesActual + 1;
    final annoBono    = mesActual == 12 ? annoActual + 1 : annoActual;
    final diasRestantes = DateTime(annoActual, mesActual + 1, 0).day - now.day;

    // BONO MAR (trabajo de febrero — CERRADO)
    final rguCerrado   = (_produccionCerrado?['promedioRGU'] as num?)?.toDouble() ?? 0.0;
    final totalCerrado = (_produccionCerrado?['totalRGU'] as num?)?.toDouble() ?? 0.0;
    final ordCerrado   = (_produccionCerrado?['ordenesCompletadas'] as num?)?.toInt() ?? 0;
    final diasCerrado  = (_produccionCerrado?['diasConProduccion'] as num?)?.toInt() ?? 0;
    final ptosCerrado  = (_produccionCerrado?['ptosHfc'] as num?)?.toDouble() ?? 0.0;
    final rguFtthCerrado = (_produccionCerrado?['rguFtth'] as num?)?.toDouble() ?? 0.0;
    final rguNeutraCerrado = (_produccionCerrado?['rguRedNeutra'] as num?)?.toDouble() ?? 0.0;
    final tipoContratoCerrado = _produccionCerrado?['tipoContrato']?.toString() ?? 'nuevo';
    final promedioPtsCerrado = (_produccionCerrado?['promedioPts'] as num?)?.toDouble() ?? 0.0;
    final mesBonoCerrado = mesCerrado == 12 ? 1 : mesCerrado + 1;

    Color _colorRGU(double rgu) {
      if (rgu <= 0) return Colors.grey[700]!;
      if (rgu < 3)  return Colors.red[700]!;
      if (rgu < 4.5) return Colors.orange[700]!;
      return Colors.green[700]!;
    }

    Color _colorPts(double pts) {
      if (pts <= 0) return Colors.grey[700]!;
      if (pts < 3)  return Colors.red[700]!;
      if (pts < 4.5) return Colors.orange[700]!;
      return Colors.green[700]!;
    }

    // Contrato antiguo: solo HFC = solo PTS; mixto = ambos totales
    bool _esContratoAntiguo(String t) {
      final u = t.toUpperCase();
      return u == 'ANTIGUO' || u == 'CA';
    }

    bool _esSoloHfc(String tipoContrato, double ptos, double rguFtth, double rguNeutra) {
      if (!_esContratoAntiguo(tipoContrato)) return false;
      return ptos > 0 && rguFtth == 0 && rguNeutra == 0;
    }

    bool _esMixto(String tipoContrato, double ptos, double rguFtth, double rguNeutra) {
      if (!_esContratoAntiguo(tipoContrato)) return false;
      return ptos > 0 && (rguFtth > 0 || rguNeutra > 0);
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProduccionScreen(mesInicial: DateTime(annoActual, mesActual)),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.trending_up, color: Colors.green[700]),
                  const SizedBox(width: 8),
                  const Text('Producción',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: Colors.grey[500]),
                ],
              ),
            ),
            const SizedBox(height: 12),

            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── BONO MAR cerrado (febrero) ──────────────────────────
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProduccionScreen(
                            mesInicial: DateTime(annoCerrado, mesCerrado),
                          ),
                        ),
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _esSoloHfc(tipoContratoCerrado, ptosCerrado, rguFtthCerrado, rguNeutraCerrado)
                              ? _colorPts(promedioPtsCerrado)
                              : _colorRGU(rguCerrado),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.lock, size: 12, color: Colors.white70),
                                const SizedBox(width: 4),
                                Text(
                                  'BONO ${_getNombreMes(mesBonoCerrado).toUpperCase()}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              _getNombreMes(mesCerrado).toUpperCase(),
                              style: const TextStyle(fontSize: 9, color: Colors.white60),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _esSoloHfc(tipoContratoCerrado, ptosCerrado, rguFtthCerrado, rguNeutraCerrado)
                                  ? promedioPtsCerrado.toStringAsFixed(1)
                                  : rguCerrado.toStringAsFixed(1),
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                            Text(
                              _esSoloHfc(tipoContratoCerrado, ptosCerrado, rguFtthCerrado, rguNeutraCerrado)
                                  ? 'PTS/día'
                                  : 'RGU/día',
                              style: const TextStyle(fontSize: 9, color: Colors.white70),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _esSoloHfc(tipoContratoCerrado, ptosCerrado, rguFtthCerrado, rguNeutraCerrado)
                                  ? '${ptosCerrado.toInt()} PTS • $ordCerrado órd.'
                                  : _esMixto(tipoContratoCerrado, ptosCerrado, rguFtthCerrado, rguNeutraCerrado)
                                      ? '${ptosCerrado.toInt()} PTS • ${totalCerrado.toInt()} RGU • $ordCerrado órd.'
                                      : '${totalCerrado.toInt()} RGU • $ordCerrado órd.',
                              style: const TextStyle(fontSize: 10, color: Colors.white70),
                            ),
                            Text(
                              '$diasCerrado días con prod.',
                              style: const TextStyle(fontSize: 9, color: Colors.white60),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('Periodo cerrado',
                                  style: TextStyle(fontSize: 8, color: Colors.white70)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // ── BONO ABR midiendo (marzo) ────────────────────────────
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProduccionScreen(
                            mesInicial: DateTime(annoActual, mesActual),
                          ),
                        ),
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _esSoloHfc(tipoContratoActual, ptosActual, rguFtthActual, rguNeutraActual)
                              ? _colorPts(promedioPtsActual)
                              : _colorRGU(rguActual),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.hourglass_top,
                                    size: 12, color: Colors.amber),
                                const SizedBox(width: 4),
                                Text(
                                  'BONO ${_getNombreMes(mesBono).toUpperCase()}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              _getNombreMes(mesActual).toUpperCase(),
                              style: const TextStyle(fontSize: 9, color: Colors.white60),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _esSoloHfc(tipoContratoActual, ptosActual, rguFtthActual, rguNeutraActual)
                                  ? promedioPtsActual.toStringAsFixed(1)
                                  : rguActual.toStringAsFixed(1),
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                            Text(
                              _esSoloHfc(tipoContratoActual, ptosActual, rguFtthActual, rguNeutraActual)
                                  ? 'PTS/día'
                                  : 'RGU/día',
                              style: const TextStyle(fontSize: 9, color: Colors.white70),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _esSoloHfc(tipoContratoActual, ptosActual, rguFtthActual, rguNeutraActual)
                                  ? '${ptosActual.toInt()} PTS • $ordActual órd.'
                                  : _esMixto(tipoContratoActual, ptosActual, rguFtthActual, rguNeutraActual)
                                      ? '${ptosActual.toInt()} PTS • ${totalActual.toInt()} RGU • $ordActual órd.'
                                      : '${totalActual.toInt()} RGU • $ordActual órd.',
                              style: const TextStyle(fontSize: 10, color: Colors.white70),
                            ),
                            Text(
                              '$diasActual días con prod.',
                              style: const TextStyle(fontSize: 9, color: Colors.white60),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Cierra en $diasRestantes días',
                                style: const TextStyle(fontSize: 8, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fila de 3 tecnologías para contrato ANTIGUO
  Widget _buildTecnologiasRow({
    required double rguNeutra,
    required double ptosHfc,
    required double rguFtth,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // RED NEUTRA
        _buildTecnoChip(
          label: 'RED NEUTRA',
          valor: '${rguNeutra.toStringAsFixed(0)} RGU',
          color: Colors.cyan[300]!,
        ),
        const SizedBox(height: 4),
        // HFC
        _buildTecnoChip(
          label: 'HFC',
          valor: '${ptosHfc.toStringAsFixed(0)} PTS',
          color: Colors.orange[300]!,
        ),
        const SizedBox(height: 4),
        // FTTH
        _buildTecnoChip(
          label: 'FTTH',
          valor: '${rguFtth.toStringAsFixed(0)} RGU',
          color: Colors.purple[300]!,
        ),
      ],
    );
  }

  Widget _buildTecnoChip({
    required String label,
    required String valor,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          '$label  ',
          style: TextStyle(fontSize: 9, color: Colors.white70, fontWeight: FontWeight.w600),
        ),
        Text(
          valor,
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Future<void> _mostrarDetalleCalidad(
    BuildContext context,
    Map<String, dynamic>? calidadData,
    String periodo,
  ) async {
    if (calidadData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos de calidad para este período')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final rutTecnico = prefs.getString('rut_tecnico');
    
    if (rutTecnico == null) return;

    // Cargar ranking de calidad
    final rankingCalidad = await _produccionService.obtenerPosicionCalidad(rutTecnico, periodo);
    
    // Cargar detalle de reiterados
    final detalleReiterados = await _produccionService.obtenerDetalleReiteradosPorPeriodo(
      rutTecnico,
      periodo,
    );

    final totalReiterados = (calidadData['total_reiterados'] as num?)?.toInt() ?? 0;
    final totalCompletadas = (calidadData['total_completadas'] as num?)?.toInt() ?? 0;
    final porcentaje = (calidadData['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;
    final promedioDias = (calidadData['promedio_dias'] as num?)?.toDouble() ?? 0.0;
    final nombreMes = _getNombreMesDesdePeriodo(periodo);
    
    final posicion = rankingCalidad['posicion'] ?? 0;
    final totalTecnicos = rankingCalidad['totalTecnicos'] ?? 0;

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _getColorCalidad(porcentaje).withOpacity(0.2),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.star, color: _getColorCalidad(porcentaje)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Reiterados - $nombreMes',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Resumen y Ranking
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Ranking
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _getColorPosicionCalidad(posicion).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _getColorPosicionCalidad(posicion).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _getIconoPosicion(posicion),
                            color: _getColorPosicionCalidad(posicion),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Posición #$posicion de $totalTecnicos',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _getColorPosicionCalidad(posicion),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Estadísticas
                    Text(
                      '$totalReiterados reiterados de $totalCompletadas completadas (${porcentaje.toStringAsFixed(1)}%)',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (promedioDias > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Promedio: ${promedioDias.toStringAsFixed(1)} días',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey[700]),
              // Lista de reiterados
              Expanded(
                child: detalleReiterados.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No hay reiterados en este período',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: detalleReiterados.length,
                        itemBuilder: (context, index) {
                          final detalle = detalleReiterados[index];
                          // Campos desde calidad_api_script
                          final fecha         = detalle['fecha']?.toString() ?? '';
                          final orden         = detalle['orden_de_trabajo']?.toString() ?? '';
                          final tipoActividad = detalle['tipo_de_actividad']?.toString() ?? '';
                          final cliente       = detalle['numero_cliente']?.toString() ?? '';
                          final zona          = detalle['zona']?.toString() ?? '';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[700],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[600]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Fecha y tipo de actividad
                                Row(
                                  children: [
                                    const Icon(Icons.calendar_today, size: 16, color: Colors.white70),
                                    const SizedBox(width: 8),
                                    Text(
                                      fecha,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    if (tipoActividad.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          tipoActividad,
                                          style: const TextStyle(
                                            color: Colors.orange,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                // Orden de trabajo
                                Row(
                                  children: [
                                    const Icon(Icons.work_outline, size: 16, color: Colors.green),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'OT: ',
                                      style: TextStyle(fontSize: 14, color: Colors.white70),
                                    ),
                                    Text(
                                      orden,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                                // Cliente
                                if (cliente.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.person, size: 16, color: Colors.white70),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Cliente: $cliente',
                                        style: const TextStyle(fontSize: 13, color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ],
                                // Zona
                                if (zona.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on, size: 16, color: Colors.white70),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Zona: ${zona.toUpperCase()}',
                                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                                      ),
                                    ],
                                  ),
                                ],
                                // Badge "Reiterado"
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.refresh, size: 16, color: Colors.red),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.red.withOpacity(0.5)),
                                      ),
                                      child: const Text(
                                        'REITERADO',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Widget para mostrar el card de Consumo completo con dos períodos
  Widget _buildCardConsumoCompleto() {
    final now = DateTime.now();
    
    // Período cerrado (mes anterior)
    final mesCerrado = now.month - 1 < 1 ? 12 : now.month - 1;
    final annoCerrado = now.month - 1 < 1 ? now.year - 1 : now.year;
    final nombreMesCerrado = _getNombreMes(mesCerrado);
    
    final totalCerrado = (_consumoCerrado?['total'] as int?) ?? 0;
    
    // Período actual (mes actual)
    final mesActual = now.month;
    final annoActual = now.year;
    final nombreMesActual = _getNombreMes(mesActual);
    final diasRestantes = DateTime(annoActual, mesActual + 1, 0).day - now.day;
    
    final totalActual = (_consumoActual?['total'] as int?) ?? 0;
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header centrado
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  const Text(
                    'Consumo Órdenes',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Dos columnas para los períodos
            IntrinsicHeight(
              child: Row(
                children: [
                  // IZQUIERDA: Período CERRADO
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ConsumoScreen()),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[850],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Título
                            Row(
                              children: [
                                const Icon(Icons.lock, size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'PENDIENTES ${nombreMesCerrado.toUpperCase()}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Total
                            Text(
                              'Total: $totalCerrado',
                              style: const TextStyle(fontSize: 12, color: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            // Estado
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey[700],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Periodo cerrado',
                                style: TextStyle(fontSize: 9, color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // DERECHA: Período ACTUAL
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ConsumoScreen()),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          border: Border.all(color: Colors.green, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Título
                            Row(
                              children: [
                                const Icon(Icons.hourglass_empty, size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'PENDIENTES ${nombreMesActual.toUpperCase()}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Total
                            Text(
                              'Total: $totalActual',
                              style: const TextStyle(fontSize: 12, color: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            // Estado
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Cierra en $diasRestantes días',
                                style: const TextStyle(fontSize: 9, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Widget para mostrar el card de Reversa completo con dos períodos
  Widget _buildCardReversaCompleto() {
    final now = DateTime.now();
    
    // Período cerrado (mes anterior)
    final mesCerrado = now.month - 1 < 1 ? 12 : now.month - 1;
    final annoCerrado = now.month - 1 < 1 ? now.year - 1 : now.year;
    final nombreMesCerrado = _getNombreMes(mesCerrado);
    
    final totalCerrado = (_reversaCerrado?['totalEquipos'] as int?) ?? 0;
    final pendientesCerrado = (_reversaCerrado?['pendientes'] as int?) ?? 0;
    final entregadosCerrado = (_reversaCerrado?['entregados'] as int?) ?? 0;
    
    // Período actual (mes actual)
    final mesActual = now.month;
    final annoActual = now.year;
    final nombreMesActual = _getNombreMes(mesActual);
    final diasRestantes = DateTime(annoActual, mesActual + 1, 0).day - now.day;
    
    final totalActual = (_reversaActual?['totalEquipos'] as int?) ?? 0;
    final pendientesActual = (_reversaActual?['pendientes'] as int?) ?? 0;
    final entregadosActual = (_reversaActual?['entregados'] as int?) ?? 0;
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header centrado
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2, color: Colors.deepOrange),
                  const SizedBox(width: 8),
                  const Text(
                    'Reversa',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Dos columnas para los períodos
            IntrinsicHeight(
              child: Row(
                children: [
                  // IZQUIERDA: Período CERRADO
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ReversaScreen()),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[850],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Título
                            Row(
                              children: [
                                const Icon(Icons.lock, size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'PENDIENTES ${nombreMesCerrado.toUpperCase()}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Total
                            Text(
                              'Total: $totalCerrado',
                              style: const TextStyle(fontSize: 12, color: Colors.white),
                            ),
                            Text(
                              'Entregados: $entregadosCerrado',
                              style: TextStyle(fontSize: 11, color: Colors.green[300]),
                            ),
                            const SizedBox(height: 8),
                            // Estado
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey[700],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Periodo cerrado',
                                style: TextStyle(fontSize: 9, color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // DERECHA: Período ACTUAL
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ReversaScreen()),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          border: Border.all(color: Colors.green, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Título
                            Row(
                              children: [
                                const Icon(Icons.hourglass_empty, size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'PENDIENTES ${nombreMesActual.toUpperCase()}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Total
                            Text(
                              'Total: $totalActual',
                              style: const TextStyle(fontSize: 12, color: Colors.white),
                            ),
                            Text(
                              'Pendientes: $pendientesActual',
                              style: TextStyle(
                                fontSize: 11,
                                color: pendientesActual > 0 ? Colors.red[300] : Colors.green[300],
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Estado
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Cierra en $diasRestantes días',
                                style: const TextStyle(fontSize: 9, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}







