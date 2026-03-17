import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trazabox/constants/app_constants.dart';
import 'package:trazabox/services/nyquist_service.dart';

const String _keplerEndpoint =
    'https://kepler.sbip.cl/api/v1/toa/get_data_toa_other_enterprise';

// ── Modelo combinado para la tabla ────────────────────────────────────────────

class _PuertoCombinado {
  final int numero;
  final double? inicial;   // Kepler: alertas.ports[n].inicial (cacheado)
  final double? rxActual;  // Nyquist: u_cto_portN_rx_actual (refreshable)
  final bool isCurrent;    // Puerto del cliente actual
  final String? portId;    // ID físico del puerto Nyquist (ej. "1/14/10/15")

  const _PuertoCombinado({
    required this.numero,
    required this.inicial,
    required this.rxActual,
    required this.isCurrent,
    this.portId,
  });

  double? get diferencia {
    if (rxActual == null || inicial == null) return null;
    return rxActual! - inicial!;
  }

  bool get esAlerta {
    if (inicial == null) return false;
    // Señal perdida: rxActual nulo o cero teniendo valor inicial
    if (rxActual == null || rxActual == 0.0) return true;
    // Atenuación: la señal bajó más de 3 dBm (diferencia negativa < -3)
    // En dBm, valores más negativos = peor señal. Una mejora (diff > 0) NO es alerta.
    final diff = diferencia;
    return diff != null && diff < -3.0;
  }
}

// ── Widget principal ──────────────────────────────────────────────────────────

class AsistenteCtoScreen extends StatefulWidget {
  const AsistenteCtoScreen({super.key});

  @override
  State<AsistenteCtoScreen> createState() => _AsistenteCtoScreenState();
}

class _AsistenteCtoScreenState extends State<AsistenteCtoScreen> {
  final NyquistService _nyquist = NyquistService();
  final TextEditingController _otManualController = TextEditingController();

  bool _cargando = true;
  bool _actualizandoEndpoint = false;
  bool _buscandoOTManual = false;
  bool _esSupervisor = false;
  String? _error;
  String? _tipoRedError;
  EstadoCTO? _resultado;
  List<PuertoKepler>? _iniciales; // Cacheado tras primer load
  String? _otActiva;
  String? _accessIdCorto;
  String? _accessIdNyquist;
  String? _nyquistError;
  String? _horaInicial;   // Hora de medición inicial (viene de Kepler)
  String? _horaFinal;     // Hora de medición final (se actualiza al refrescar)

  static const Color _bgColor = Color(0xFF0D1B2A);
  static const Color _surfaceColor = Color(0xFF1A2C3D);
  static const Color _cyanColor = Color(0xFF00BCD4);
  static const Color _alertRed = Color(0xFFE53935);


  @override
  void initState() {
    super.initState();
    _initRol().then((_) => _cargarYConsultar());
  }

  Future<void> _initRol() async {
    final prefs = await SharedPreferences.getInstance();
    final rol = prefs.getString('user_rol') ?? 'tecnico';
    _esSupervisor = rol == 'supervisor' || rol == 'ito';
  }

  @override
  void dispose() {
    _otManualController.dispose();
    super.dispose();
  }

  /// Carga completa: Supabase → Kepler iniciales (1 vez) → Nyquist finales
  Future<void> _cargarYConsultar() async {
    setState(() {
      _cargando = true;
      _error = null;
      _tipoRedError = null;
      _nyquistError = null;
      _resultado = null;
    });

    try {
      // ── Paso 0: IDs de trabajo desde Supabase ──────────────────────────
      {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final rut = prefs.getString('rut_tecnico') ?? '';

        if (rut.isEmpty) {
          setState(() { _cargando = false; _error = 'sin_trabajo'; });
          return;
        }

        debugPrint('🔍 [AsistenteCTO] Buscando access_id para RUT: $rut');
        final supabaseResult = await _nyquist.buscarAccessIdPorRut(rut);
        debugPrint('🔍 [AsistenteCTO] Supabase resultado: $supabaseResult');

        if (supabaseResult == null) {
          setState(() { _cargando = false; _error = 'sin_trabajo'; });
          return;
        }

        final tipoRed = (supabaseResult['tipo_red_producto'] ?? '').toString();
        if (tipoRed.isNotEmpty && tipoRed.toUpperCase() != 'NFTT') {
          setState(() {
            _cargando = false;
            _error = 'tecnologia_incompatible';
            _tipoRedError = tipoRed.toUpperCase();
          });
          return;
        }

        final accessIdPrefijado = (supabaseResult['access_id'] ?? '').toString();
        if (accessIdPrefijado.isEmpty) {
          setState(() {
            _cargando = false;
            _error = 'tecnologia_incompatible';
            _tipoRedError = null;
          });
          return;
        }

        _accessIdNyquist = accessIdPrefijado;

        final ot = (supabaseResult['orden_de_trabajo'] ?? '').toString().trim();
        _accessIdCorto = ot.isNotEmpty
            ? ot
            : accessIdPrefijado.replaceFirst(RegExp(r'^\d{1,2}-'), '');
        _otActiva = supabaseResult['id_actividad']?.toString() ?? _accessIdCorto;

        debugPrint('🔑 [AsistenteCTO] OT→Kepler: $_accessIdCorto | AccessID→Nyquist: $_accessIdNyquist');
      }

      // ── Paso 1: Kepler Traza (iniciales, solo si no están cacheadas) ─────
      if (_iniciales == null) {
        debugPrint('🌐 [AsistenteCTO] Cargando iniciales desde Kepler...');
        try {
          _iniciales = await _nyquist.fetchIniciales(_accessIdCorto!);
          _horaInicial = _nyquist.lastKeplerHoraInicial;
          debugPrint('✅ [AsistenteCTO] Iniciales cargadas: ${_iniciales!.length} puertos | Hora: $_horaInicial');
        } catch (e) {
          debugPrint('⚠️ [AsistenteCTO] Kepler no disponible: $e');
          _iniciales = [];
        }
      } else {
        debugPrint('📦 [AsistenteCTO] Usando iniciales cacheadas: ${_iniciales!.length} puertos');
      }

      // ── Paso 2: Nyquist (finales) ────────────────────────────────────────
      debugPrint('🌐 [AsistenteCTO] Consultando Nyquist...');
      try {
        final resultado = await _nyquist.consultarEstado(_accessIdNyquist!);
        if (mounted) setState(() { _resultado = resultado; _horaFinal = _formatHoraAhora(); _cargando = false; });
      } catch (e) {
        debugPrint('⚠️ [AsistenteCTO] Nyquist error: $e');
        if (mounted) {
          setState(() {
            _nyquistError = e.toString().replaceFirst('Exception: ', '');
            _resultado = null;
            _cargando = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _cargando = false;
        });
      }
    }
  }

  /// Actualizar solo Nyquist (NO vuelve a Kepler, mantiene iniciales cacheadas)
  Future<void> _actualizarEndpoint() async {
    if (_accessIdNyquist == null) return;
    setState(() => _actualizandoEndpoint = true);

    try {
      final resultado = await _nyquist.consultarEstado(_accessIdNyquist!);
      if (mounted) {
        setState(() {
          _resultado = resultado;
          _horaFinal = _formatHoraAhora();
          _actualizandoEndpoint = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _actualizandoEndpoint = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar: ${e.toString().replaceFirst("Exception: ", "")}'),
            backgroundColor: _alertRed,
          ),
        );
      }
    }
  }

  /// Construye la lista combinada cruzando Kepler (iniciales) con Nyquist (finales)
  List<_PuertoCombinado> _buildPuertosCombinados() {
    // Kepler indexado por número de puerto (1-8)
    final keplerMap = {
      for (final k in (_iniciales ?? [])) k.portNumber: k,
    };

    // Nyquist: dos índices para cubrir ambos casos de matching
    final nyquistBySuffix = <String, PuertoCTO>{};
    final nyquistByNum    = <int, PuertoCTO>{};
    for (final p in (_resultado?.puertos ?? [])) {
      final suffix = p.portSuffix;
      if (suffix != null) nyquistBySuffix[suffix] = p;
      nyquistByNum[p.numero] = p;
    }

    // Primera pasada: registrar qué números de puerto Nyquist ya fueron
    // consumidos por suffix-matching. Si el fallback secuencial usara el
    // mismo puerto que ya asignó el matching por sufijo, aparecería
    // duplicado (mismo rxActual en dos filas distintas).
    final nyquistNumerosConsumidos = <int>{};
    for (int pn = 1; pn <= 8; pn++) {
      final kSuffix = keplerMap[pn]?.portSuffix;
      if (kSuffix != null) {
        final matched = nyquistBySuffix[kSuffix];
        if (matched != null) nyquistNumerosConsumidos.add(matched.numero);
      }
    }

    // Segunda pasada: construir los 8 puertos combinados
    return List.generate(8, (i) {
      final portNum = i + 1;
      final k = keplerMap[portNum];

      PuertoCTO? n;
      final kSuffix = k?.portSuffix;
      if (kSuffix != null) {
        // Matching principal: cruzar por último segmento del ID físico
        n = nyquistBySuffix[kSuffix];
      } else {
        // Fallback secuencial: solo si ese número Nyquist no fue ya
        // asignado a otra fila por el matching de sufijo
        final candidate = nyquistByNum[portNum];
        if (candidate != null &&
            !nyquistNumerosConsumidos.contains(candidate.numero)) {
          n = candidate;
        }
      }

      return _PuertoCombinado(
        numero: portNum,
        inicial: k?.inicial,
        rxActual: n?.rxActual,
        isCurrent: k?.isCurrent ?? false,
        portId: null,
      );
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _surfaceColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          children: [
            Icon(Icons.router, color: Color(0xFF00BCD4), size: 22),
            SizedBox(width: 10),
            Text(
              'Asistente de CTO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      body: _buildCuerpo(),
    );
  }

  Widget _buildCuerpo() {
    if (_cargando) return _buildCargando();
    if (_error == 'sin_trabajo') {
      return _esSupervisor ? _buildInputManualSupervisor() : _buildSinTrabajo();
    }
    if (_error == 'tecnologia_incompatible') return _buildTecnologiaIncompatible();
    // mantener compatibilidad con registros antiguos
    if (_error == 'otra_tecnologia') return _buildTecnologiaIncompatible();
    if (_error != null) return _buildError();
    // Mostrar tabla si hay datos de alguna fuente (siempre 8 puertos)
    if (_iniciales != null || _resultado != null || _nyquistError != null) return _buildResultado();
    return _buildCargando();
  }

  // ── Estados ───────────────────────────────────────────────────────────────

  Widget _buildCargando() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: _cyanColor),
          const SizedBox(height: 20),
          Text(
            _iniciales == null
                ? 'Cargando niveles iniciales...'
                : 'Actualizando medición final...',
            style: const TextStyle(color: Colors.white70, fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Input manual para supervisor/ITO ────────────────────────────────────

  Widget _buildInputManualSupervisor() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.manage_search, size: 72, color: _cyanColor),
            const SizedBox(height: 24),
            const Text(
              'Consulta manual de CTO',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              'No hay órdenes Iniciadas para tu RUT.\nIngresa la Orden de Trabajo a consultar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.white54, height: 1.5),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _otManualController,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'Ej: 1-3IRTCLXQ',
                hintStyle: const TextStyle(color: Colors.white38),
                labelText: 'Orden de Trabajo (OT)',
                labelStyle: const TextStyle(color: _cyanColor),
                prefixIcon: const Icon(Icons.assignment, color: _cyanColor),
                filled: true,
                fillColor: _surfaceColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _cyanColor, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _cyanColor.withOpacity(0.4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _cyanColor, width: 2),
                ),
              ),
              onSubmitted: (_) => _consultarOTManual(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _buscandoOTManual ? null : _consultarOTManual,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _cyanColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _buscandoOTManual
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black54,
                        ),
                      )
                    : const Icon(Icons.search),
                label: Text(
                  _buscandoOTManual ? 'Buscando...' : 'Consultar OT',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Supervisor ingresó OT manualmente → buscar access_id en Supabase → flujo normal
  Future<void> _consultarOTManual() async {
    final ot = _otManualController.text.trim().toUpperCase();
    if (ot.isEmpty) return;

    setState(() {
      _buscandoOTManual = true;
      _error = null;
      _iniciales = null;
    });

    try {
      // Buscar access_id por OT en la tabla access_id
      final resp = await _nyquist.buscarAccessIdPorOT(ot);
      if (resp == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('OT "$ot" no encontrada en la base de datos.'),
              backgroundColor: _alertRed,
            ),
          );
          setState(() => _buscandoOTManual = false);
        }
        return;
      }

      final tipoRed = (resp['tipo_red_producto'] ?? '').toString().toUpperCase();
      if (tipoRed.isNotEmpty && tipoRed != 'NFTT') {
        if (mounted) {
          setState(() {
            _buscandoOTManual = false;
            _error = 'tecnologia_incompatible';
            _tipoRedError = tipoRed;
          });
        }
        return;
      }

      final accessIdPrefijado = resp['access_id']?.toString() ?? '';
      if (accessIdPrefijado.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('La OT encontrada no tiene access_id asignado.'),
              backgroundColor: _alertRed,
            ),
          );
          setState(() => _buscandoOTManual = false);
        }
        return;
      }

      // Tenemos los IDs → continuar con flujo normal
      _accessIdNyquist = accessIdPrefijado;
      _accessIdCorto = ot; // Usar OT para Kepler
      _otActiva = ot;

      setState(() {
        _buscandoOTManual = false;
        _error = null;
        _cargando = true;
      });

      // Paso 1: Kepler iniciales
      try {
        _iniciales = await _nyquist.fetchIniciales(_accessIdCorto!);
        _horaInicial = _nyquist.lastKeplerHoraInicial;
      } catch (e) {
        debugPrint('⚠️ [CTO-Supervisor] Kepler no disponible: $e');
        _iniciales = [];
      }

      // Paso 2: Nyquist
      try {
        final resultado = await _nyquist.consultarEstado(_accessIdNyquist!);
        if (mounted) {
          setState(() {
            _resultado = resultado;
            _horaFinal = _formatHoraAhora();
            _cargando = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _nyquistError = e.toString().replaceFirst('Exception: ', '');
            _resultado = null;
            _cargando = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [CTO-Supervisor] Error en consulta manual: $e');
      if (mounted) {
        setState(() => _buscandoOTManual = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: _alertRed,
          ),
        );
      }
    }
  }

  Widget _buildSinTrabajo() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.work_off_outlined, size: 72, color: Colors.white30),
            const SizedBox(height: 24),
            const Text('Sin trabajo activo',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 12),
            const Text(
              'No se encontró ninguna orden en estado "Iniciado".\nEl Asistente CTO requiere una orden activa.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.white54, height: 1.5),
            ),
            const SizedBox(height: 32),
            _buildBotonActualizar(onPressed: _cargarYConsultar),
          ],
        ),
      ),
    );
  }

  Widget _buildTecnologiaIncompatible() {
    // Mensaje personalizado según la tecnología detectada
    final tipo = _tipoRedError ?? '';
    final String mensaje;
    final IconData icono;
    final Color color;

    if (tipo.contains('FTTH')) {
      mensaje = 'ORDEN FTTH\nSOLO PUEDO MEDIR RED NEUTRA';
      icono = Icons.settings_input_component;
      color = Colors.purple[300]!;
    } else if (tipo.contains('HFC')) {
      mensaje = 'ORDEN HFC\nSOLO PUEDO MEDIR RED NEUTRA';
      icono = Icons.cable;
      color = Colors.orange[300]!;
    } else {
      mensaje = 'Este trabajo pertenece a una tecnología\ndiferente a NFTT';
      icono = Icons.fiber_manual_record;
      color = Colors.orange;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, size: 72, color: color),
            const SizedBox(height: 24),
            Text(
              tipo.isNotEmpty ? 'Orden $tipo detectada' : 'Tecnología no compatible',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withOpacity(0.45)),
              ),
              child: Text(
                mensaje,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: color,
                  height: 1.5,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 32),
            _buildBotonActualizar(onPressed: _cargarYConsultar),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: _alertRed),
            const SizedBox(height: 20),
            const Text(
              'Error al consultar CTO',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _alertRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _alertRed.withOpacity(0.4)),
              ),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _alertRed, fontSize: 13, height: 1.4),
              ),
            ),
            const SizedBox(height: 24),
            _buildBotonActualizar(onPressed: _cargarYConsultar),
          ],
        ),
      ),
    );
  }

  // ── Resultado principal ───────────────────────────────────────────────────

  Widget _buildResultado() {
    final puertos = _buildPuertosCombinados();

    return Column(
      children: [
        // Botón Actualizar (solo Nyquist)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _actualizandoEndpoint
              ? const SizedBox(
                  height: 48,
                  child: Center(child: CircularProgressIndicator(color: _cyanColor)),
                )
              : _buildBotonActualizar(onPressed: _actualizarEndpoint),
        ),

        // Tabla de puertos
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.table_chart, color: _cyanColor, size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Detalles de Alertas y Niveles de Puertos',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                // Badge con el Access ID / OT que se está midiendo
                if (_accessIdCorto != null || _accessIdNyquist != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _cyanColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _cyanColor.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cable, color: _cyanColor, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'Orden: ${_accessIdCorto ?? '-'}',
                          style: const TextStyle(
                            color: _cyanColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Aviso si Nyquist falló pero tenemos iniciales
                if (_nyquistError != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Medición final no disponible. Presiona Actualizar para reintentar.',
                            style: TextStyle(color: Colors.orange, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _buildTablaPuertos(puertos),
                const SizedBox(height: 16),
                _buildHorasConsulta(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHorasConsulta() {
    if (_horaInicial == null && _horaFinal == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time, color: _cyanColor, size: 16),
              const SizedBox(width: 6),
              const Text(
                'Tiempos de Consulta',
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildHoraItem(
                  label: 'Consulta Inicial',
                  hora: _horaInicial ?? '--:--',
                  color: Colors.green[300]!,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildHoraItem(
                  label: 'Consulta Final',
                  hora: _horaFinal ?? '--:--',
                  color: _cyanColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHoraItem({required String label, required String hora, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color.withOpacity(0.75), fontSize: 10, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(hora, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _buildTablaPuertos(List<_PuertoCombinado> puertos) {
    if (puertos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Sin puertos activos reportados',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Encabezado
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0D2137),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                _thCell('Pto', flex: 2),
                _thCell('C1\nInicial', flex: 3),
                _thCell('C2\nFinal', flex: 3),
                _thCell('Dif.', flex: 3),
                _thCell('Ok', flex: 2),
              ],
            ),
          ),

          // Filas
          ...puertos.asMap().entries.map((entry) {
            final isLast = entry.key == puertos.length - 1;
            return _buildFilaPuerto(entry.value, isLast: isLast);
          }),
        ],
      ),
    );
  }

  Widget _buildFilaPuerto(_PuertoCombinado p, {required bool isLast}) {
    final esAlerta = p.esAlerta;
    final diff = p.diferencia;

    final consulta1 = p.inicial != null ? p.inicial!.toStringAsFixed(2) : '-';
    final consulta2 = (p.rxActual != null) ? p.rxActual!.toStringAsFixed(2) : '-';
    final diferencia = diff != null ? diff.toStringAsFixed(2) : '0.00';

    // Verde si no hay dato, si mejoró (diff > 0) o la caída es ≤ 3 dBm.
    // Rojo solo si la caída supera -3 dBm o señal perdida.
    final diffColor = diff == null
        ? Colors.white54
        : diff >= -3.0
            ? Colors.green
            : _alertRed;

    return Container(
      decoration: BoxDecoration(
        color: esAlerta ? _alertRed.withOpacity(0.15) : Colors.transparent,
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : BorderSide(color: Colors.white.withOpacity(0.07), width: 1),
        ),
        borderRadius: isLast
            ? const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              )
            : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Row(
        children: [
          // Puerto (badge rojo si alerta, cyan si es el puerto actual)
          Expanded(
            flex: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: esAlerta
                        ? _alertRed
                        : p.isCurrent
                            ? _cyanColor
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${p.numero}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: (esAlerta || p.isCurrent)
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ),
                // (ID físico oculto — el matching se hace internamente por portSuffix)
              ],
            ),
          ),

          // Consulta1 (Inicial / Kepler)
          Expanded(
            flex: 3,
            child: Text(
              consulta1,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
            ),
          ),

          // Consulta2 (Final / Nyquist)
          Expanded(
            flex: 3,
            child: Text(
              consulta2,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.rxActual == null ? Colors.white30 : Colors.white,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),

          // Diferencia
          Expanded(
            flex: 3,
            child: Text(
              diferencia,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: diffColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),

          // Estado: solo ícono para ahorrar espacio
          Expanded(
            flex: 2,
            child: Center(
              child: esAlerta
                  ? const Icon(Icons.warning_amber_rounded, color: _alertRed, size: 18)
                  : const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Hora actual en formato "HH:MM AM/PM" (igual que Kepler)
  String _formatHoraAhora() {
    final now = TimeOfDay.now();
    final h = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
    final m = now.minute.toString().padLeft(2, '0');
    final period = now.period == DayPeriod.am ? 'AM' : 'PM';
    return '${h.toString().padLeft(2, '0')}:$m $period';
  }

  Widget _thCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _buildBotonActualizar({required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.refresh, color: Colors.white),
        label: const Text(
          'Actualizar',
          style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _cyanColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
