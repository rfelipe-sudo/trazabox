import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/produccion_service.dart';
import '../models/calidad_tecnico.dart';

class CalidadScreen extends StatefulWidget {
  const CalidadScreen({super.key});

  @override
  State<CalidadScreen> createState() => _CalidadScreenState();
}

class _CalidadScreenState extends State<CalidadScreen> {
  final ProduccionService _service = ProduccionService();
  Map<String, dynamic>? _calidadData;
  List<DetalleReiterado> _detalleReiterados = [];
  bool _cargando = true;
  String? _tecnicoRut;
  int _periodoOffset = 0; // 0 = período actual, -1 = anterior, etc.
  final PageController _pageController = PageController(initialPage: 100);

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String get _periodoSeleccionado {
    final now = DateTime.now();
    
    // Calcular período base (actual o anterior según día del mes)
    String periodoBase;
    if (now.day <= 20) {
      // Período actual: este mes
      periodoBase = _service.getPeriodoActual();
    } else {
      // Período actual: próximo mes
      periodoBase = _service.getPeriodoActual();
    }
    
    // Aplicar offset para navegar entre períodos
    if (_periodoOffset != 0) {
      final partes = periodoBase.split('-');
      if (partes.length == 2) {
        final anno = int.tryParse(partes[0]) ?? now.year;
        final mes = int.tryParse(partes[1]) ?? now.month;
        final fecha = DateTime(anno, mes + _periodoOffset, 1);
        return _service.getPeriodoDesdeMesAnno(fecha.month, fecha.year);
      }
    }
    
    return periodoBase;
  }

  Color get _colorPrincipal {
    return _periodoOffset == 0 ? Colors.amber[700]! : Colors.blue[700]!;
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);

    final prefs = await SharedPreferences.getInstance();
    _tecnicoRut = prefs.getString('rut_tecnico');

    if (_tecnicoRut != null) {
      final periodo = _periodoSeleccionado;
      _calidadData = await _service.obtenerCalidadPorPeriodo(_tecnicoRut!, periodo);
      
      // Cargar detalle de reiterados
      if (_calidadData != null) {
        final totalReiterados = (_calidadData!['total_reiterados'] as num?)?.toInt() ?? 0;
        if (totalReiterados > 0) {
          _detalleReiterados = await _service.obtenerDetalleReiterados(_tecnicoRut!);
          
          // Filtrar por período (fecha_original debe estar en el período)
          final partesPeriodo = periodo.split('-');
          if (partesPeriodo.length == 2) {
            final annoPeriodo = int.tryParse(partesPeriodo[0]) ?? 0;
            final mesPeriodo = int.tryParse(partesPeriodo[1]) ?? 0;
            
            _detalleReiterados = _detalleReiterados.where((detalle) {
              final partesFecha = detalle.fechaOriginal.split('/');
              if (partesFecha.length == 3) {
                final annoFecha = int.tryParse(partesFecha[2]) ?? 0;
                final mesFecha = int.tryParse(partesFecha[1]) ?? 0;
                return annoFecha == annoPeriodo && mesFecha == mesPeriodo;
              }
              return false;
            }).toList();
            
            // Ordenar por fecha descendente (más reciente primero)
            _detalleReiterados.sort((a, b) {
              try {
                final partesA = a.fechaOriginal.split('/');
                final partesB = b.fechaOriginal.split('/');
                if (partesA.length == 3 && partesB.length == 3) {
                  final fechaA = DateTime(
                    int.parse(partesA[2]),
                    int.parse(partesA[1]),
                    int.parse(partesA[0]),
                  );
                  final fechaB = DateTime(
                    int.parse(partesB[2]),
                    int.parse(partesB[1]),
                    int.parse(partesB[0]),
                  );
                  return fechaB.compareTo(fechaA); // Descendente
                }
              } catch (e) {
                // Si hay error, mantener orden original
              }
              return 0;
            });
          }
        }
      }
      
      print('✅ [Calidad] Período: $periodo, Total reiterados: ${_calidadData?['total_reiterados'] ?? 0}');
    }

    setState(() => _cargando = false);
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

  String _getNombreMes(int mes) {
    const meses = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
                   'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    return meses[mes];
  }

  Color _getColorCalidad(double porcentaje) {
    if (porcentaje <= 4.0) return Colors.green;      // Excelente (≤ 4%)
    if (porcentaje <= 5.7) return Colors.orange;     // Regular (4.1% - 5.7%)
    return Colors.red;                                // Necesita mejorar (> 5.8%)
  }

  @override
  Widget build(BuildContext context) {
    final nombreMes = _getNombreMesDesdePeriodo(_periodoSeleccionado);
    final porcentaje = (_calidadData?['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;
    final totalReiterados = (_calidadData?['total_reiterados'] as num?)?.toInt() ?? 0;
    final totalCompletadas = (_calidadData?['total_completadas'] as num?)?.toInt() ?? 0;
    final promedioDias = (_calidadData?['promedio_dias'] as num?)?.toDouble() ?? 0.0;
    
    final colorCalidad = _getColorCalidad(porcentaje);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Calidad - $nombreMes',
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: _colorPrincipal,
        foregroundColor: Colors.white,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: _pageController,
              itemCount: 200, // 100 es el centro (período actual), permite navegación completa
              onPageChanged: (page) {
                final newOffset = page - 100; // 100 es el centro
                setState(() {
                  _periodoOffset = newOffset;
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
                        // Header con resumen del período
                    Card(
                      elevation: 4,
                          color: colorCalidad,
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.all(20),
                            childrenPadding: const EdgeInsets.only(bottom: 16),
                            title: Column(
                          children: [
                                // Indicador de período con flechas
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
                                        '$nombreMes ${_periodoSeleccionado.split('-')[0]}',
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
                                // Porcentaje de reiteración
                                Text(
                                  porcentaje > 0 
                                      ? '${porcentaje.toStringAsFixed(1)}%'
                                      : '0.0%',
                                  style: const TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const Text(
                                  'Reiteración',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white70,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Fila de indicadores secundarios
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _buildMiniStat('Reiterados', '$totalReiterados'),
                                    _buildMiniStat('Completadas', '$totalCompletadas'),
                                    if (promedioDias > 0)
                                      _buildMiniStat('Promedio', '${promedioDias.toStringAsFixed(1)}d'),
                                  ],
                                ),
                              ],
                            ),
                            children: [
                              // Lista de reiterados dentro del ExpansionTile
                              if (_detalleReiterados.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    children: [
                                      const Icon(Icons.check_circle, size: 48, color: Colors.white70),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'No hay reiterados en este período',
                                        style: TextStyle(color: Colors.white70),
                                    textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ..._detalleReiterados.map((detalle) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.2),
                                          width: 1,
                                        ),
                                      ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                          // Fecha de instalación
                                          Row(
                                            children: [
                                              const Icon(Icons.calendar_today, size: 16, color: Colors.white70),
                                              const SizedBox(width: 8),
                                        Text(
                                                'Fecha de instalación: ${detalle.fechaOriginal}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          // Orden y fecha de reparación
                                        Row(
                                          children: [
                                              const Icon(Icons.refresh, size: 16, color: Colors.white70),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Orden: ${detalle.ordenReiterada} - Fecha: ${detalle.fechaReiterada}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          // Causa
                                          if (detalle.causa.isNotEmpty) ...[
                                            const SizedBox(height: 12),
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                                                const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                      const Text(
                                                        'Causa:',
                                                        style: TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                  Text(
                                                        detalle.causa,
                                                        style: const TextStyle(
                                                          color: Colors.orange,
                                                          fontSize: 14,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                          ],
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                      ),
                    ),
                  ],
                ),
              ),
                );
              },
            ),
    );
  }

  Widget _buildMiniStat(String label, String valor) {
    return Column(
      children: [
        Text(
          valor,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildTipoChip(String label, int valor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Text(
        '$label: $valor',
        style: const TextStyle(
          color: Colors.blue,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildDetalleItem(String label, String valor, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.white70),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
