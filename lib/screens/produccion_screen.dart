import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/produccion_service.dart';
import '../services/nyquist_service.dart';
import '../models/metrica_produccion.dart';
import '../widgets/creaciones_loading.dart';

class ProduccionScreen extends StatefulWidget {
  final DateTime? mesInicial;
  
  const ProduccionScreen({super.key, this.mesInicial});

  @override
  _ProduccionScreenState createState() => _ProduccionScreenState();
}

class _ProduccionScreenState extends State<ProduccionScreen> {
  final ProduccionService _service = ProduccionService();
  final NyquistService _nyquistService = NyquistService();
  Map<String, dynamic> _resumenMes = {};
  List<Map<String, dynamic>> _detalleDiario = [];
  Map<String, dynamic> _rankingData = {};
  Map<String, dynamic> _metricasTiempo = {};
  bool _cargando = true;
  String? _tecnicoRut;
  String? _tipoRedProducto;
  int _mesOffset = 0; // 0 = mes actual, -1 = mes anterior, etc.
  final PageController _pageController = PageController(initialPage: 100);

  @override
  void initState() {
    super.initState();
    // Si se pasó un mes inicial, calcular el offset
    if (widget.mesInicial != null) {
      final now = DateTime.now();
      _mesOffset = widget.mesInicial!.month - now.month + 
                   (widget.mesInicial!.year - now.year) * 12;
    }
    _cargarDatos();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime get _mesSeleccionado {
    final now = DateTime.now();
    return DateTime(now.year, now.month + _mesOffset, 1);
  }

  Color get _colorPrincipal {
    return _mesOffset == 0 ? Colors.green[700]! : Colors.blue[700]!;
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    
    final prefs = await SharedPreferences.getInstance();
    _tecnicoRut = prefs.getString('rut_tecnico');
    
    if (_tecnicoRut != null) {
      // Obtener tipo de red del técnico (en paralelo con el resumen)
      _nyquistService.obtenerTipoRedTecnico(_tecnicoRut!).then((tipo) {
        if (mounted && tipo != null) setState(() => _tipoRedProducto = tipo);
      });

      // Pasar el mes seleccionado al servicio
      _resumenMes = await _service.obtenerResumenMesRGU(
        _tecnicoRut!,
        mes: _mesSeleccionado.month,
        anno: _mesSeleccionado.year,
      );
      
      // Debug
      print('📊 Resumen cargado: $_resumenMes');
      
      _detalleDiario = await _service.obtenerDetallePorDiaRGU(
        _tecnicoRut!,
        mes: _mesSeleccionado.month,
        anno: _mesSeleccionado.year,
      );
      
      // Obtener ranking
      _rankingData = await _service.obtenerPosicionTecnico(
        _tecnicoRut!,
        mes: _mesSeleccionado.month,
        anno: _mesSeleccionado.year,
      );
      print('🏆 Ranking: $_rankingData');

      // Recalcular posición usando el promedio real de la card (GeoVictoria incluida).
      // Actualiza TANTO el header como el renglón propio dentro de la lista.
      final promedioReal = (_resumenMes?['promedioRGU'] as num?)?.toDouble();
      print('🔢 [Ranking] promedioReal (card): $promedioReal | posicion original: ${_rankingData['posicion']}');
      if (promedioReal != null && _rankingData.containsKey('top10')) {
        // 1. Actualizar el promedioRGU del usuario en la lista con el valor correcto
        final todosRaw = List<Map<String, dynamic>>.from(_rankingData['top10'] as List);
        final todosActualizados = todosRaw.map((t) {
          if (t['rut'] == _tecnicoRut) {
            return Map<String, dynamic>.from(t)..['promedioRGU'] = promedioReal;
          }
          return t;
        }).toList();

        // 2. Re-ordenar lista completa con el promedio corregido del usuario
        todosActualizados.sort((a, b) {
          final pa = (a['promedioRGU'] as num?)?.toDouble() ?? 0.0;
          final pb = (b['promedioRGU'] as num?)?.toDouble() ?? 0.0;
          return pb.compareTo(pa); // mayor promedio primero
        });

        // 3. Reasignar posiciones
        for (int i = 0; i < todosActualizados.length; i++) {
          todosActualizados[i] = Map<String, dynamic>.from(todosActualizados[i])
            ..['posicion'] = i + 1;
        }

        // 4. Encontrar nueva posición del usuario
        final nuevaPosicion = todosActualizados.indexWhere((t) => t['rut'] == _tecnicoRut) + 1;
        print('🔢 [Ranking] nueva posicion: $nuevaPosicion / ${todosActualizados.length}');

        _rankingData = {
          ..._rankingData,
          'posicion': nuevaPosicion > 0 ? nuevaPosicion : _rankingData['posicion'],
          'top10': todosActualizados,
        };
      }
      
      // Obtener métricas de tiempo
      _metricasTiempo = await _service.obtenerMetricasTiempo(
        _tecnicoRut!,
        mes: _mesSeleccionado.month,
        anno: _mesSeleccionado.year,
      );
      print('⏱️ Métricas tiempo: $_metricasTiempo');
    }
    
    setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    final nombreMes = _getNombreMes(_mesSeleccionado.month);
    
    // Calcular el nombre del bono (mes siguiente al trabajo)
    final mesTrabajo = _mesSeleccionado.month;
    final annoTrabajo = _mesSeleccionado.year;
    final mesBono = mesTrabajo + 1 > 12 ? 1 : mesTrabajo + 1;
    final annoBono = mesTrabajo + 1 > 12 ? annoTrabajo + 1 : annoTrabajo;
    final nombreMesBono = _getNombreMes(mesBono);
    final diasMes = DateTime(annoTrabajo, mesTrabajo + 1, 0).day;
    
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'BONO DE PRODUCCIÓN ${nombreMesBono.toUpperCase()}',
              style: const TextStyle(fontSize: 16),
          overflow: TextOverflow.ellipsis,
            ),
            Text(
              '01/$nombreMes - $diasMes/$nombreMes',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: _colorPrincipal,
        foregroundColor: Colors.white,
      ),
      body: _cargando
          ? const CreacionesLoading(
              mensaje: 'Cargando datos de producción...',
            )
          : PageView.builder(
              controller: _pageController,
              itemCount: 200, // 100 es el centro (mes actual), permite navegación completa
              onPageChanged: (page) {
                final newOffset = page - 100; // 100 es el centro
                  setState(() {
                    _mesOffset = newOffset;
                  });
                  _cargarDatos();
              },
              itemBuilder: (context, index) {
                return RefreshIndicator(
                  onRefresh: _cargarDatos,
                  color: _colorPrincipal,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header resumen del mes con ExpansionTile para detalle por día
                        Card(
                          elevation: 4,
                          color: _colorPrincipal,
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.all(20),
                            childrenPadding: const EdgeInsets.only(bottom: 16),
                            title: Column(
                              children: [
                                // Indicador de mes con flechas
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.chevron_left, color: Colors.white),
                                      onPressed: () {
                                        _pageController.previousPage(
                                          duration: const Duration(milliseconds: 300),
                                          curve: Curves.easeInOut,
                                        );
                                      },
                                    ),
                                    Flexible(
                                      child: Text(
                                        '$nombreMes ${_mesSeleccionado.year}',
                                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.chevron_right,
                                        color: Colors.white,
                                      ),
                                      onPressed: () {
                                              _pageController.nextPage(
                                                duration: const Duration(milliseconds: 300),
                                                curve: Curves.easeInOut,
                                              );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // Badge de tecnología
                                if (_tipoRedProducto != null && _tipoRedProducto!.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white.withOpacity(0.4)),
                                    ),
                                    child: Text(
                                      _tipoRedProducto!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                // Promedio RGU - CORREGIDO
                                Text(
                                  (_resumenMes['promedioRGU'] != null)
                                      ? (_resumenMes['promedioRGU'] as num).toStringAsFixed(1)
                                      : '0.0',
                                  style: const TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const Text(
                                  'RGU/día',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white70,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                // Total RGU y Órdenes (centrados y lado a lado)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Total: ${(_resumenMes['totalRGU'] as num?)?.toInt() ?? 0} RGU',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Container(
                                      height: 20,
                                      width: 1,
                                      margin: const EdgeInsets.symmetric(horizontal: 16),
                                      color: Colors.white.withOpacity(0.3),
                                    ),
                                    Text(
                                      'Órdenes: ${_resumenMes['ordenesCompletadas'] ?? 0}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                // Desglose por tecnología (solo contrato antiguo)
                                if ((_resumenMes['tipoContrato']?.toString() ?? 'nuevo') == 'antiguo') ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildTecnoChipBono(
                                        'RED NEUTRA',
                                        '${((_resumenMes['rguRedNeutra'] as num?)?.toInt() ?? 0)} RGU',
                                        Colors.blue[300]!,
                                      ),
                                      const SizedBox(width: 8),
                                      _buildTecnoChipBono(
                                        'HFC',
                                        '${((_resumenMes['ptosHfc'] as num?)?.toInt() ?? 0)} PTS',
                                        Colors.orange[300]!,
                                      ),
                                      const SizedBox(width: 8),
                                      _buildTecnoChipBono(
                                        'FTTH',
                                        '${((_resumenMes['rguFtth'] as num?)?.toInt() ?? 0)} RGU',
                                        Colors.purple[300]!,
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 16),
                                // Info de días operativos y turno
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.calendar_today, size: 16, color: Colors.white70),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Turno ${_resumenMes['tipoTurno'] ?? '5x2'} • ${_resumenMes['diasOperativos'] ?? 22} días operativos',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Grid de días: Trabajados, Ausentes, Feriados, Vacaciones
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 16,
                                  runSpacing: 8,
                                  children: [
                                    _buildMiniStat('Trabajados', '${_resumenMes['diasTrabajados'] ?? 0}'),
                                    _buildMiniStat('Ausentes', '${_resumenMes['diasAusentes'] ?? 0}', color: Colors.red),
                                    _buildMiniStat('Feriados', '${_resumenMes['feriados'] ?? 0}', color: Colors.orange),
                                    _buildMiniStat('Vacaciones', '${_resumenMes['vacaciones'] ?? 0}'),
                                  ],
                                ),
                              ],
                            ),
                            children: [
                              // Detalle por día dentro del ExpansionTile
                              if (_detalleDiario.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    children: [
                                      const Icon(Icons.inbox, size: 48, color: Colors.white70),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'No hay producción registrada este mes',
                                        style: TextStyle(color: Colors.white70),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ..._detalleDiario.map((dia) {
                                  final fecha = dia['fecha'] as String;
                                  final ordenes = dia['ordenesCompletadas'] as int;
                                  final ordenesDetalle = dia['ordenes'] as List<Map<String, dynamic>>;

                                  // Formatear fecha para mostrar (soporta DD/MM/YY y DD.MM.YY)
                                  final partesFecha = fecha.replaceAll('.', '/').split('/');
                                  String fechaFormateada = fecha;
                                  if (partesFecha.length == 3) {
                                    final annoStr = partesFecha[2];
                                    final anno = annoStr.length == 2 ? 2000 + int.parse(annoStr) : int.parse(annoStr);
                                    final dt = DateTime(anno, int.parse(partesFecha[1]), int.parse(partesFecha[0]));
                                    const dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
                                    fechaFormateada = '${dias[dt.weekday - 1]} ${partesFecha[0]}.${partesFecha[1]}.${partesFecha[2]}';
                                  }

                                  // Tecnologías presentes en el día
                                  final tecnologiasDia = (dia['tecnologias'] as List?)?.cast<String>() ?? [];
                                  final tieneMultiTecno = tecnologiasDia.length > 1;
                                  final tipoContrato = _resumenMes['tipoContrato']?.toString() ?? 'nuevo';
                                  final rguNeutraDia = (dia['rguRedNeutra'] as num?)?.toDouble() ?? 0.0;
                                  final ptosHfcDia = (dia['ptosHfc'] as num?)?.toDouble() ?? 0.0;
                                  final rguFtthDia = (dia['rguFtth'] as num?)?.toDouble() ?? 0.0;

                                  return Card(
                                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    color: Colors.grey[800],
                                    child: ExpansionTile(
                                      textColor: Colors.white,
                                      iconColor: Colors.white,
                                      title: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Fecha siempre horizontal (una línea)
                                          Text(
                                            fechaFormateada,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              fontSize: 15,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            softWrap: false,
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Text(
                                                '$ordenes ${ordenes == 1 ? "orden" : "órdenes"}',
                                                style: const TextStyle(color: Colors.white70, fontSize: 14),
                                              ),
                                              const SizedBox(width: 16),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: _colorPrincipal.withOpacity(0.3),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  '${_formatRGU((dia['rguTotal'] as num).toDouble())} RGU',
                                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ],
                                          ),
                                          // Desglose por tecnología (contrato antiguo o multi-tecno)
                                          if (tipoContrato == 'antiguo' || tieneMultiTecno) ...[
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: [
                                                if (rguNeutraDia > 0)
                                                  _buildTecnoTag('RED NEUTRA', '${rguNeutraDia.toStringAsFixed(0)} RGU', Colors.cyan[300]!),
                                                if (ptosHfcDia > 0)
                                                  _buildTecnoTag('HFC', '${ptosHfcDia.toStringAsFixed(0)} PTS', Colors.orange[300]!),
                                                if (rguFtthDia > 0)
                                                  _buildTecnoTag('FTTH', '${rguFtthDia.toStringAsFixed(0)} RGU', Colors.purple[300]!),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                      children: ordenesDetalle.map((orden) {
                                        final ot = orden['orden_trabajo']?.toString() ?? '';
                                        final tipo = orden['tipo_orden']?.toString() ?? '';
                                        final tecno = _tipoRedProducto ?? orden['tecnologia']?.toString() ?? 'RED_NEUTRA';
                                        final rguBase = (orden['rgu_base'] as num?)?.toDouble() ?? 0;
                                        final rguAdicional = (orden['rgu_adicional'] as num?)?.toDouble() ?? 0;
                                        final rguOrden = (orden['rgu_total'] as num?)?.toDouble() ?? 0;
                                        final ptsHfcOrden = (orden['puntos_hfc'] as num?)?.toDouble() ?? 0;
                                        final categoriaHfc = orden['categoria_hfc']?.toString() ?? '';
                                        final dbox = (orden['cant_dbox'] as num?)?.toInt() ?? 0;
                                        final extensores = (orden['cant_extensores'] as num?)?.toInt() ?? 0;

                                        // Construir lista de componentes del RGU usando valores directos de Supabase
                                        List<Map<String, dynamic>> componentes = [];

                                        // 1. Base siempre presente
                                        String baseLabel = 'Base $tipo';
                                        if (tipo.contains('Modificación')) {
                                          baseLabel = 'Base modificación';
                                        } else if (tipo.contains('Reparación')) {
                                          baseLabel = 'Base reparación';
                                        } else if (tipo.contains('Play')) {
                                          baseLabel = 'Base ${tipo.replaceAll('Alta ', '').replaceAll('Migración ', '')}';
                                        }
                                        componentes.add({'label': baseLabel, 'valor': rguBase});

                                        // 2. Solo mostrar adicionales si hay rgu_adicional > 0 (valor directo de Supabase)
                                        if (rguAdicional > 0) {
                                          // Determinar label descriptivo basado en equipos
                                          String labelAdicional = 'Adicional';
                                          
                                          if (tipo.contains('Modificación')) {
                                            // Modificación: mostrar equipos adicionales
                                            final totalEquipos = dbox + extensores;
                                            if (totalEquipos > 1) {
                                              final equiposAdicionales = totalEquipos - 1;
                                              if (dbox > 0 && extensores > 0) {
                                                labelAdicional = 'Equipos adicionales ($equiposAdicionales)';
                                              } else if (dbox > 1) {
                                                labelAdicional = 'D-Box adicionales (${dbox - 1})';
                                              } else if (extensores > 1) {
                                                labelAdicional = 'Extensores adicionales (${extensores - 1})';
                                              } else {
                                                labelAdicional = 'Equipo adicional';
                                              }
                                            } else {
                                              labelAdicional = 'Adicional';
                                            }
                                          } else {
                                            // Altas y Migraciones: mostrar equipos
                                            if (dbox > 2) {
                                              final dboxAdicionales = dbox - 2;
                                              labelAdicional = dboxAdicionales == 1 
                                                  ? 'D-Box adicional' 
                                                  : 'D-Box adicionales ($dboxAdicionales)';
                                            } else if (extensores > 0) {
                                              labelAdicional = extensores == 1 
                                                  ? 'Extensor' 
                                                  : 'Extensores ($extensores)';
                                            } else {
                                              labelAdicional = 'Adicional';
                                            }
                                          }
                                          
                                          // Usar el valor directo de rgu_adicional de Supabase
                                          componentes.add({'label': labelAdicional, 'valor': rguAdicional});
                                        }

                                        return Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // OT siempre horizontal (una línea)
                                              Text(
                                                'OT: $ot',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  color: Colors.white,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                softWrap: false,
                                              ),
                                              const SizedBox(height: 4),
                                              // Tipo, badge y RGU debajo
                                              Row(
                                                children: [
                                                  Text(
                                                    tipo,
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  _buildTecnoBadge(tecno),
                                                  const SizedBox(width: 8),
                                                  if (tecno == 'HFC')
                                                    Text(
                                                      '${ptsHfcOrden.toStringAsFixed(0)} PTS',
                                                      style: TextStyle(
                                                        color: Colors.orange[300],
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 14,
                                                      ),
                                                    )
                                                  else
                                                    Text(
                                                      '${_formatRGU(rguOrden)} RGU',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              // Categoría HFC si aplica
                                              if (tecno == 'HFC' && categoriaHfc.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Padding(
                                                  padding: const EdgeInsets.only(left: 16),
                                                  child: Text(
                                                    'Categoría HFC: $categoriaHfc',
                                                    style: TextStyle(fontSize: 11, color: Colors.orange[200]),
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 4),
                                              // Desglose de componentes (solo para no-HFC)
                                              ...componentes.asMap().entries.map((entry) {
                                                final isLast = entry.key == componentes.length - 1;
                                                final prefix = isLast ? '└─' : '├─';
                                                return Padding(
                                                  padding: const EdgeInsets.only(left: 16),
                                                  child: Text(
                                                    '$prefix ${entry.value['label']}: ${_formatRGU(entry.value['valor'])}',
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                );
                                              }),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  );
                                }).toList(),
                            ],
                          ),
                        ),
                    
                    const SizedBox(height: 20),
                    
                    // Estadísticas del mes
                    const Text('Resumen del Mes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    // Cards de kilómetros y combustible - OCULTADAS (para uso futuro)
                    if (false) ...[
                      Row(
                        children: [
                          Expanded(child: _buildStatCard(
                            icon: Icons.speed,
                            color: Colors.purple,
                            titulo: 'Km recorridos',
                            valor: '${((_resumenMes['kmTotales'] ?? 0) as num).toDouble().toStringAsFixed(1)}',
                            subtitulo: 'km',
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: _buildStatCard(
                            icon: Icons.local_gas_station,
                            color: Colors.red,
                            titulo: 'Combustible',
                            valor: '${((_resumenMes['combustibleTotal'] ?? 0) as num).toDouble().toStringAsFixed(1)}',
                            subtitulo: 'litros',
                          )),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.trending_up,
                                    color: _getColorEfectividad((_resumenMes['efectividad'] ?? 0.0) as double),
                                    size: 28,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${((_resumenMes['efectividad'] ?? 0.0) as num).toDouble().toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: _getColorEfectividad((_resumenMes['efectividad'] ?? 0.0) as double),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Efectividad',
                                    style: TextStyle(color: Colors.grey, fontSize: 14),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${_resumenMes['ordenesCompletadas'] ?? 0} completadas',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                    textAlign: TextAlign.center,
                                  ),
                                  Text(
                                    '${_resumenMes['ordenesCanceladas'] ?? 0} canceladas',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                    textAlign: TextAlign.center,
                                  ),
                                  Text(
                                    '${_resumenMes['ordenesNoRealizadas'] ?? 0} no realizadas',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.cancel_outlined,
                                    color: _getColorQuiebre((_resumenMes['porcentajeQuiebre'] ?? 0.0) as double),
                                    size: 28,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${((_resumenMes['porcentajeQuiebre'] ?? 0.0) as num).toDouble().toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: _getColorQuiebre((_resumenMes['porcentajeQuiebre'] ?? 0.0) as double),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    '% Quiebre',
                                    style: TextStyle(color: Colors.grey, fontSize: 14),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${_resumenMes['ordenesAsignadas'] ?? 0} asignadas',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                    textAlign: TextAlign.center,
                                  ),
                                  Text(
                                    '${_resumenMes['ordenesCanceladas'] ?? 0} canceladas',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                    textAlign: TextAlign.center,
                                  ),
                                  Text(
                                    '${_resumenMes['ordenesNoRealizadas'] ?? 0} no realizadas',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Card de Días PX-0 (siempre visible)
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: (_resumenMes['diasPX0'] ?? 0) > 0 ? Colors.orange[900] : Colors.grey[800],
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.all(16),
                        childrenPadding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
                        title: Row(
                          children: [
                            Icon(
                              (_resumenMes['diasPX0'] ?? 0) > 0 ? Icons.warning_amber : Icons.check_circle_outline,
                              color: (_resumenMes['diasPX0'] ?? 0) > 0 ? Colors.orange : Colors.green,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Días PX-0',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    (_resumenMes['diasPX0'] ?? 0) > 0
                                        ? '${_resumenMes['diasPX0']} día(s) con asignaciones pero sin completadas'
                                        : 'Sin días PX-0 este mes',
                                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        children: [
                          if ((_resumenMes['diasPX0'] ?? 0) > 0 && _resumenMes['diasPX0List'] != null)
                            ...(_resumenMes['diasPX0List'] as List<Map<String, dynamic>>).map((diaInfo) {
                              final fecha = diaInfo['fecha'] as String;
                              final ordenes = diaInfo['ordenes'] as int;
                              
                              // Formatear fecha (soporta DD/MM/YY y DD.MM.YY)
                              final partesFecha = fecha.replaceAll('.', '/').split('/');
                              String fechaFormateada = fecha;
                              if (partesFecha.length == 3) {
                                final annoStr = partesFecha[2];
                                final anno = annoStr.length == 2 ? 2000 + int.parse(annoStr) : int.parse(annoStr);
                                final dt = DateTime(anno, int.parse(partesFecha[1]), int.parse(partesFecha[0]));
                                const diasSemana = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
                                const meses = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
                                fechaFormateada = '${diasSemana[dt.weekday - 1]} ${partesFecha[0]}.${partesFecha[1]}.${partesFecha[2]}';
                              }
                              
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[800],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.calendar_today, color: Colors.orange[300], size: 16),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            fechaFormateada,
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            softWrap: false,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.orange[700],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '$ordenes orden${ordenes != 1 ? 'es' : ''}',
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            })
                          else
                            // Mensaje cuando no hay PX-0
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.celebration, color: Colors.green[300], size: 24),
                                  const SizedBox(width: 8),
                                  const Text(
                                    '¡Excelente! Sin días PX-0',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Card de Ranking (ExpansionTile)
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: Colors.grey[900],
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.all(16),
                        childrenPadding: const EdgeInsets.only(bottom: 16),
                        title: Row(
                          children: [
                            Icon(
                              Icons.emoji_events,
                              color: _getColorPosicion(_rankingData['posicion'] ?? 0),
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Tu posición en el ranking',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  Text(
                                    '#${_rankingData['posicion'] ?? '-'} de ${_rankingData['totalTecnicos'] ?? '-'}',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: _getColorPosicion(_rankingData['posicion'] ?? 0),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Promedio RGU del técnico
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  // Usar el promedio del resumen individual con mismo redondeo que la card
                                  ((_resumenMes?['promedioRGU'] ?? _rankingData['promedioRGU'] ?? 0) as num).toDouble().toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const Text(
                                  'RGU/día',
                                  style: TextStyle(fontSize: 12, color: Colors.white70),
                                ),
                              ],
                            ),
                          ],
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Divider(height: 24, color: Colors.white24),
                                // Título del ranking con info de días operativos
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                const Text(
                                      'Ranking completo',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                    ),
                                    Text(
                                      '${_rankingData['totalTecnicos'] ?? 0} técnicos',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                // Info de días operativos y turno del técnico actual
                                if (_rankingData['diasTrabajados'] != null && _rankingData['diasTrabajados'] > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Icon(Icons.info_outline, size: 14, color: Colors.white60),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Tu turno: ${_rankingData['tipoTurno'] ?? '5x2'} • ${_rankingData['diasTrabajados']} días operativos',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white60,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                // Mostrar TODOS los técnicos, no solo top 10
                                ...(_rankingData['top10'] as List? ?? []).asMap().entries.map((entry) {
                              final index = entry.key;
                              final tecnico = entry.value;
                              final posicion = tecnico['posicion'];
                              final nombre = tecnico['nombre'] ?? '';
                              final rgu = (tecnico['rguTotal'] as num?)?.toDouble() ?? 0;
                              final esYo = tecnico['rut'] == _tecnicoRut;
                              // Para la fila propia usar el promedio calculado individualmente
                              // (considera GeoVictoria y días reales), los demás usan el del ranking
                              final promedioRGU = esYo
                                  ? ((_resumenMes?['promedioRGU'] ?? tecnico['promedioRGU']) as num).toDouble()
                                  : (tecnico['promedioRGU'] as num?)?.toDouble() ?? 0.0;
                              // Para la fila propia, formatear igual que la card (toStringAsFixed → redondea)
                              // _formatPromedio trunca, lo que puede dar 2.7 en vez de 2.8
                              final promedioTexto = esYo
                                  ? promedioRGU.toStringAsFixed(1)
                                  : null; // null = usar _formatPromedio del widget

                              return Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                    margin: const EdgeInsets.only(bottom: 4),
                                decoration: BoxDecoration(
                                      color: esYo 
                                          ? _colorPrincipal.withOpacity(0.3) 
                                          : Colors.grey[850],
                                  borderRadius: BorderRadius.circular(8),
                                      border: esYo 
                                          ? Border.all(color: _colorPrincipal, width: 2)
                                          : null,
                                ),
                                child: Row(
                                  children: [
                                    // Posición con medalla para top 3
                                    SizedBox(
                                          width: 40,
                                      child: posicion <= 3
                                          ? Icon(
                                              Icons.emoji_events,
                                              color: posicion == 1
                                                  ? Colors.amber
                                                  : posicion == 2
                                                      ? Colors.grey[400]
                                                      : Colors.orange[700],
                                                  size: 24,
                                            )
                                          : Text(
                                              '#$posicion',
                                                  style: TextStyle(
                                                    fontWeight: esYo ? FontWeight.bold : FontWeight.w600,
                                                color: Colors.white,
                                                    fontSize: esYo ? 16 : 14,
                                              ),
                                            ),
                                    ),
                                    // Nombre
                                    Expanded(
                                      child: Text(
                                        nombre,
                                        style: TextStyle(
                                          fontWeight: esYo ? FontWeight.bold : FontWeight.normal,
                                          color: Colors.white,
                                              fontSize: esYo ? 15 : 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // Promedio RGU
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          promedioTexto ?? _formatPromedio(promedioRGU),
                                              style: TextStyle(
                                                fontWeight: esYo ? FontWeight.bold : FontWeight.w600,
                                            color: Colors.white,
                                                fontSize: esYo ? 18 : 16,
                                          ),
                                        ),
                                        Text(
                                          'RGU/día',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Card de Métricas de Tiempo
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.timer, color: _colorPrincipal, size: 24),
                                const SizedBox(width: 8),
                                const Text(
                                  'Tiempos del mes',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),

                            // Métricas principales en grid
                            Row(
                              children: [
                                Expanded(
                                  child: _buildMetricaTiempo(
                                    'Prom/Orden',
                                    _formatearMinutos((_metricasTiempo['tiempoPromedioOrden'] ?? 0) as int),
                                    Icons.assignment,
                                    Colors.blue,
                                  ),
                                ),
                                Expanded(
                                  child: _buildMetricaTiempo(
                                    'Órdenes/Día',
                                    ((_metricasTiempo['ordenesPorDia'] ?? 0) as num).toStringAsFixed(1),
                                    Icons.format_list_numbered,
                                    Colors.green,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            
                            // Inicio tardío destacado con detalle
                            Card(
                              color: Colors.red,
                              child: ExpansionTile(
                                tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                childrenPadding: const EdgeInsets.only(bottom: 12),
                                iconColor: Colors.white,
                                collapsedIconColor: Colors.white,
                                leading: const Icon(
                                  Icons.alarm_off,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: const Text(
                                        'Inicio tardío: ',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      _formatearMinutos((_metricasTiempo['tiempoInicioTardio'] ?? 0) as int),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: _buildDetalleInicioTardio(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Horas extras (nuevo)
                            _buildHorasExtrasCard(),
                            const SizedBox(height: 16),

                            // Distribución del tiempo
                            const Text(
                              'Distribución de la jornada',
                              style: TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                            const SizedBox(height: 8),

                            // Barra visual de distribución
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                height: 32,
                                child: _buildBarraTiempoNueva(),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Leyenda detallada
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                _buildLeyendaTiempo(
                                  'Trabajando',
                                  _formatearMinutos((_metricasTiempo['tiempoTrabajoTotal'] ?? 0) as int),
                                  Colors.green,
                                ),
                                _buildLeyendaTiempo(
                                  'Ocio',
                                  _formatearMinutos((_metricasTiempo['tiempoSinActividad'] ?? 0) as int),
                                  Colors.red,
                                ),
                                _buildLeyendaTiempo(
                                  'Ruta',
                                  _formatearMinutos((_metricasTiempo['tiempoTrayectoTotal'] ?? 0) as int),
                                  Colors.amber[700]!,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                  ],
                ),
              ),
                );
              },
            ),
    );
  }

  Widget _buildMiniStat(String titulo, String valor, {Color? color}) {
    return Column(
      children: [
        Text(valor, style: TextStyle(color: color ?? Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        Text(titulo, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Widget _buildTimeCard({
    required IconData icon,
    required Color color,
    required String titulo,
    required int minutos,
  }) {
    final horas = minutos ~/ 60;
    final mins = minutos % 60;
    final tiempo = horas > 0 ? '${horas}h ${mins}m' : '${mins}m';
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(tiempo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(titulo, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color color,
    required String titulo,
    required String valor,
    required String subtitulo,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(valor, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(titulo, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
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

  String _getDiaSemana(int dia) {
    const dias = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return dias[dia];
  }

  Color _getColorEfectividad(double valor) {
    if (valor >= 70) return Colors.green[700]!;
    if (valor >= 50) return Colors.orange[700]!;
    return Colors.red[700]!;
  }

  Color _getColorQuiebre(double valor) {
    if (valor <= 20) return Colors.green[700]!;
    if (valor <= 35) return Colors.orange[700]!;
    return Colors.red[700]!;
  }


  Color _getColorPosicion(int posicion) {
    if (posicion == 0) return Colors.grey;
    if (posicion == 1) return Colors.amber[700]!;
    if (posicion == 2) return Colors.grey[600]!;
    if (posicion == 3) return Colors.orange[700]!;
    if (posicion <= 10) return Colors.green[700]!;
    if (posicion <= 20) return Colors.blue[700]!;
    return Colors.grey[700]!;
  }

  /// Chip de tecnología para el título del día (desglose multi-tecno)
  /// Chip grande para el desglose de tecnologías en la card principal del Bono
  Widget _buildTecnoChipBono(String label, String valor, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        border: Border.all(color: color.withOpacity(0.8)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(valor, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTecnoTag(String label, String valor, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Text(valor, style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// Badge pequeño para indicar la tecnología de cada orden
  Widget _buildTecnoBadge(String tecnologia) {
    Color color;
    String label;
    switch (tecnologia.toUpperCase()) {
      case 'HFC':
        color = Colors.orange[400]!;
        label = 'HFC';
        break;
      case 'FTTH':
        color = Colors.purple[400]!;
        label = 'FTTH';
        break;
      case 'NFTT':
        color = Colors.cyan[400]!;
        label = 'NFTT';
        break;
      default:
        color = Colors.cyan[400]!;
        label = 'NEUTRA';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
    );
  }

  String _formatRGU(double valor) {
    // Si es entero (1.0, 2.0, 3.0), mostrar sin decimales
    if (valor == valor.truncateToDouble()) {
      return valor.toInt().toString();
    }
    // Si tiene decimales, siempre mostrar 2 decimales
    return valor.toStringAsFixed(2);
  }

  /// Formatear promedio truncando (no redondeando) a 1 decimal
  /// Ejemplo: 4.98 -> "4.9" (no "5.0")
  String _formatPromedio(double valor) {
    // Truncar a 1 decimal: multiplicar por 10, truncar, dividir por 10
    final truncado = (valor * 10).truncate() / 10;
    return truncado.toStringAsFixed(1);
  }

  Widget _buildMetricaTiempo(String label, String valor, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            valor,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBarraTiempo() {
    final trabajo = (_metricasTiempo['tiempoTrabajoTotal'] ?? 0) as int;
    final trayecto = (_metricasTiempo['tiempoTrayectoTotal'] ?? 0) as int;
    final ocio = (_metricasTiempo['tiempoOcioTotal'] ?? 0) as int;
    final total = trabajo + trayecto + ocio;

    if (total == 0) {
      return Container(
        color: Colors.grey[200],
        alignment: Alignment.center,
        child: const Text(
          'Sin datos',
          style: TextStyle(color: Colors.grey, fontSize: 10),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final anchoTotal = constraints.maxWidth;
        final anchoTrabajo = total > 0 ? (trabajo / total) * anchoTotal : 0.0;
        final anchoOcio = total > 0 ? (ocio / total) * anchoTotal : 0.0;
        final anchoRuta = total > 0 ? (trayecto / total) * anchoTotal : 0.0;

        return Row(
          children: [
            // Trabajo (verde con letras blancas)
            if (trabajo > 0 && anchoTrabajo > 0)
              Container(
                width: anchoTrabajo,
                color: Colors.green,
                alignment: Alignment.center,
                child: const Text(
                  'Trabajo',
                  style: TextStyle(color: Colors.white, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            // Ocio (gris con letras blancas)
            if (ocio > 0 && anchoOcio > 0)
              Container(
                width: anchoOcio,
                color: Colors.grey[600],
                alignment: Alignment.center,
                child: const Text(
                  'Ocio',
                  style: TextStyle(color: Colors.white, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            // Ruta (amarillo con letras blancas)
            if (trayecto > 0 && anchoRuta > 0)
              Container(
                width: anchoRuta,
                color: Colors.amber[700],
                alignment: Alignment.center,
                child: const Text(
                  'Ruta',
                  style: TextStyle(color: Colors.white, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBarraTiempoNueva() {
    final trabajo = (_metricasTiempo['tiempoTrabajoTotal'] ?? 0) as int;
    final ocio = (_metricasTiempo['tiempoSinActividad'] ?? 0) as int;
    final ruta = (_metricasTiempo['tiempoTrayectoTotal'] ?? 0) as int;
    final total = trabajo + ocio + ruta;

    if (total == 0) {
      return Container(
        color: Colors.grey[200],
        alignment: Alignment.center,
        child: const Text(
          'Sin datos',
          style: TextStyle(color: Colors.grey, fontSize: 10),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final anchoTotal = constraints.maxWidth;
        final anchoTrabajo = total > 0 ? (trabajo / total) * anchoTotal : 0.0;
        final anchoOcio = total > 0 ? (ocio / total) * anchoTotal : 0.0;
        final anchoRuta = total > 0 ? (ruta / total) * anchoTotal : 0.0;

        return Row(
          children: [
            // Trabajo efectivo (verde)
            if (trabajo > 0 && anchoTrabajo > 0)
              Expanded(
                flex: trabajo.clamp(1, 9999),
                child: Container(
                  color: Colors.green,
                  alignment: Alignment.center,
                  child: const Text(
                    'Trabajando',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            // Ocio (rojo)
            if (ocio > 0 && anchoOcio > 0)
              Expanded(
                flex: ocio.clamp(1, 9999),
                child: Container(
                  color: Colors.red,
                  alignment: Alignment.center,
                  child: const Text(
                    'Ocio',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            // Ruta (amarillo)
            if (ruta > 0 && anchoRuta > 0)
              Expanded(
                flex: ruta.clamp(1, 9999),
                child: Container(
                  color: Colors.amber[700],
                  alignment: Alignment.center,
                  child: const Text(
                    'Ruta',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildLeyendaTiempo(String label, String valor, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label: $valor',
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }

  String _formatearMinutos(int minutos) {
    if (minutos <= 0) return '0m';
    final horas = minutos ~/ 60;
    final mins = minutos % 60;
    if (horas > 0 && mins > 0) return '${horas}h ${mins}m';
    if (horas > 0) return '${horas}h';
    return '${mins}m';
  }

  Color _getColorProductividad(num valor) {
    if (valor >= 70) return Colors.green[700]!;
    if (valor >= 50) return Colors.orange[700]!;
    return Colors.red[700]!;
  }

  Widget _buildDetalleInicioTardio() {
    final detalle = (_metricasTiempo['detalleInicioTardio'] as List?) ?? [];
    
    if (detalle.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No hay días con inicio tardío',
          style: TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Detalle por día:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        ...detalle.map((item) {
          final fecha = item['fecha']?.toString() ?? '';
          final horaInicio = item['horaInicio']?.toString() ?? '00:00';
          final retraso = (item['retraso'] as num?)?.toInt() ?? 0;
          final esSabado = item['esSabado'] as bool? ?? false;
          
          // Formatear fecha
          final partesFecha = fecha.split('/');
          String fechaFormateada = fecha;
          if (partesFecha.length == 3) {
            final dt = DateTime(
              int.parse(partesFecha[2]),
              int.parse(partesFecha[1]),
              int.parse(partesFecha[0]),
            );
            const dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
            fechaFormateada = '${dias[dt.weekday - 1]} ${partesFecha[0]}/${partesFecha[1]}';
          }
          
          final horaEsperada = esSabado ? '10:00' : '9:45';
          
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: Colors.red[800],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fechaFormateada,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Inicio: $horaInicio (esperado: $horaEsperada)',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _formatearMinutos(retraso),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildHorasExtrasCard() {
    final total = (_metricasTiempo['horasExtrasTotal'] as num?)?.toInt() ?? 0;

    return Card(
      color: _colorPrincipal,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: total > 0 ? _mostrarDetalleHorasExtras : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.more_time, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              const Text(
                'Horas extras: ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              Expanded(
                child: Text(
                  _formatearMinutos(total),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
              if (total > 0)
                const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarDetalleHorasExtras() {
    final detalle = (_metricasTiempo['detalleHorasExtras'] as List?) ?? [];
    final total = (_metricasTiempo['horasExtrasTotal'] as num?)?.toInt() ?? 0;

    // El detalle ya viene agrupado por semana desde el servicio
    List<Map<String, dynamic>> semanas = detalle
        .where((item) => (item as Map<String, dynamic>)['tipo'] == 'semana')
        .cast<Map<String, dynamic>>()
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        if (detalle.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '⏰ Mis Horas Extras',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Text(
                  'No hay horas extras registradas',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final maxHeight = MediaQuery.of(context).size.height * 0.65;
        final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: bottomPadding + 12),
            child: SizedBox(
              height: maxHeight,
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '⏰ Mis Horas Extras',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: semanas.isEmpty
                        ? const Center(
                            child: Text(
                              'No hay horas extras registradas',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : ListView.separated(
                            itemCount: semanas.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final semana = semanas[index] as Map<String, dynamic>;
                              final inicioSemana = semana['inicioSemana'] as int? ?? 1;
                              final finSemana = semana['finSemana'] as int? ?? 7;
                              final mes = semana['mes'] as int? ?? DateTime.now().month;
                              final anno = semana['anno'] as int? ?? DateTime.now().year;
                              final totalMinutos = semana['totalMinutos'] as int? ?? 0;
                              final dias = semana['dias'] as List<Map<String, dynamic>>? ?? [];

                              final nombreMes = _getNombreMes(mes);
                              final rangoSemana = 'Semana del $inicioSemana al $finSemana $nombreMes';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey[850],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey[700]!,
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header de la semana
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: _colorPrincipal.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            Icons.calendar_today,
                                            color: _colorPrincipal,
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            rangoSemana,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    // Días de la semana
                                    ...dias.map((dia) {
                                      final fecha = dia['fecha']?.toString() ?? '';
                                      final minutos = (dia['horasExtrasMin'] as num?)?.toInt() ?? 0;
                                      final esSabado = dia['esSabado'] as bool? ?? false;
                                      final horaFin = dia['horaFin']?.toString() ?? '';

                                      final partes = fecha.split('/');
                                      String fechaFormateada = fecha;
                                      if (partes.length == 3) {
                                        fechaFormateada = '${partes[0]}/${partes[1]}/${partes[2]}';
                                      }
                                      if (esSabado) {
                                        fechaFormateada = '$fechaFormateada (Sáb)';
                                      }

                                      final detallesLinea =
                                          'Última finalización: ${horaFin.isNotEmpty ? horaFin : '-'}';

                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 10),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[800],
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      if (esSabado)
                                                        Container(
                                                          margin: const EdgeInsets.only(right: 6),
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: Colors.amber.withOpacity(0.2),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: const Text(
                                                            'SÁB',
                                                            style: TextStyle(
                                                              color: Colors.amber,
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ),
                                                      Text(
                                                        fechaFormateada,
                                                        style: TextStyle(
                                                          color: esSabado ? Colors.amber : Colors.white,
                                                          fontSize: 15,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.access_time,
                                                        size: 12,
                                                        color: Colors.grey[400],
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        detallesLinea,
                                                        style: TextStyle(
                                                          color: Colors.grey[400],
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    _colorPrincipal.withOpacity(0.3),
                                                    _colorPrincipal.withOpacity(0.2),
                                                  ],
                                                ),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: _colorPrincipal.withOpacity(0.5),
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: Text(
                                                _formatearMinutos(minutos),
                                                style: TextStyle(
                                                  color: _colorPrincipal,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    // Total de la semana al final
                                    const Divider(color: Colors.white12, height: 24),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            _colorPrincipal.withOpacity(0.2),
                                            _colorPrincipal.withOpacity(0.1),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: _colorPrincipal.withOpacity(0.4),
                                          width: 2,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Row(
                                            children: [
                                              Icon(
                                                Icons.summarize,
                                                color: Colors.white70,
                                                size: 18,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'Total semana:',
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            _formatearMinutos(totalMinutos),
                                            style: TextStyle(
                                              color: _colorPrincipal,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _colorPrincipal.withOpacity(0.25),
                          _colorPrincipal.withOpacity(0.15),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _colorPrincipal.withOpacity(0.5),
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.calculate,
                              color: Colors.white,
                              size: 24,
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Total:',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _colorPrincipal.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _colorPrincipal,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            _formatearMinutos(total),
                            style: TextStyle(
                              color: _colorPrincipal,
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
