import 'package:supabase_flutter/supabase_flutter.dart';
import 'produccion_service.dart';

/// Servicio de calidad para TrazaBox.
/// Fuente de datos: tabla `calidad_api_script` en Supabase.
///
/// Lógica de períodos:
///   - El campo `periodo` en BD = MES DE TRABAJO (actividades medidas)
///   - BONO del mes M = mide trabajo del mes M-1
///   - Ej: BONO MAR (marzo) → periodo "02-2026" (trabajo febrero)
///   - Ej: BONO ABR (abril) → periodo "03-2026" (trabajo marzo)
///
/// Formato del campo `periodo` en BD: "MM-YYYY" = mes de trabajo
class CalidadTrazaService {
  static final CalidadTrazaService _instance = CalidadTrazaService._internal();
  factory CalidadTrazaService() => _instance;
  CalidadTrazaService._internal();

  final _supabase = Supabase.instance.client;

  /// Usa ProduccionService.cuentaComoProduccion para consistencia con Producción
  static bool _cuentaComoProduccion(dynamic orden) =>
      ProduccionService.cuentaComoProduccion(orden);

  /// Evalúa si es_reiterado indica reiteración (acepta bool, int 1, "true", "SI")
  static bool _esReiterado(dynamic val) {
    if (val == null) return false;
    if (val == true || val == 1) return true;
    final s = val.toString().trim().toUpperCase();
    return s == 'TRUE' || s == 'SI' || s == 'YES' || s == '1';
  }

  // ── Helpers de período ────────────────────────────────────────────────────

  String _formatPeriodo(int mes, int anno) =>
      '${mes.toString().padLeft(2, '0')}-$anno';

  /// Período CERRADO: mes de trabajo del bono ya cerrado.
  /// Hoy 6 MAR → BONO FEB cerrado → trabajo enero → "01-2026"
  String getPeriodoCerrado() {
    final now = DateTime.now();
    final trabajoCerrado = DateTime(now.year, now.month - 2, 1);
    return _formatPeriodo(trabajoCerrado.month, trabajoCerrado.year);
  }

  /// Período MIDIENDO: mes de trabajo del bono en curso.
  /// Hoy 6 MAR → BONO MAR midiendo → trabajo febrero → "02-2026"
  String getPeriodoMidiendo() {
    final now = DateTime.now();
    final trabajoActual = DateTime(now.year, now.month - 1, 1);
    return _formatPeriodo(trabajoActual.month, trabajoActual.year);
  }

  /// Período PRÓXIMO: mes de trabajo del próximo bono.
  /// Hoy 6 MAR → BONO ABR próximo → trabajo marzo → "03-2026"
  String getPeriodoProximo() {
    final now = DateTime.now();
    return _formatPeriodo(now.month, now.year);
  }

  // ── Consulta principal ────────────────────────────────────────────────────

  /// Obtiene métricas de calidad para el período.
  /// total_completadas = produccion si hay datos; si no, calidad_api_script (evita ceros)
  /// total_reiterados = desde calidad_api_script
  Future<Map<String, dynamic>?> obtenerCalidadPorPeriodo(
    String rut,
    String periodo,
  ) async {
    try {
      final variantes = _rutVariantesCalidad(rut);
      if (variantes.isEmpty) return null;

      // 1. Reiterados y detalle — rut_o_bucket puede diferir del RUT guardado en prefs
      List<Map<String, dynamic>> ordenes = [];
      for (final per in {periodo, _periodoAlternativo(periodo)}) {
        try {
          final response = await _supabase
              .from('calidad_api_script')
              .select()
              .inFilter('rut_o_bucket', variantes)
              .eq('periodo', per)
              .limit(3000);
          ordenes = List<Map<String, dynamic>>.from(response as List);
          if (ordenes.isNotEmpty) break;
        } catch (_) {}
      }
      final completadasCalidad = ordenes
          .where((o) => o['estado']?.toString() == 'Completado')
          .length;
      final reiteradosValidos = ordenes.where((o) => _esReiterado(o['es_reiterado'])).toList();

      // Total: SIEMPRE preferir produccion (mismo que Producción); si 0, usar calidad_api_script
      final totalProduccion = await _obtenerTotalProduccionMes(rut, periodo);
      final totalCompletadas = totalProduccion > 0 ? totalProduccion : completadasCalidad;
      if (totalCompletadas == 0) return null;

      final porcentaje = totalCompletadas > 0
          ? reiteradosValidos.length / totalCompletadas * 100
          : 0.0;

      double promedioDias = 0;
      if (reiteradosValidos.isNotEmpty) {
        double totalDias = 0;
        int contados = 0;
        for (final o in reiteradosValidos) {
          final orig = _parseFecha(o['fecha']?.toString() ?? '');
          final reit = _parseFecha(o['reiterada_por_fecha']?.toString() ?? '');
          if (orig != null && reit != null) {
            totalDias += reit.difference(orig).inDays.toDouble().abs();
            contados++;
          }
        }
        if (contados > 0) promedioDias = totalDias / contados;
      }

      return {
        'periodo': periodo,
        'total_completadas': totalCompletadas,
        'total_reiterados': reiteradosValidos.length,
        'porcentaje_reiteracion': porcentaje,
        'promedio_dias': promedioDias,
        'detalle': reiteradosValidos,
      };
    } catch (e) {
      print('❌ [CalidadTraza] Error obteniendo calidad: $e');
      return null;
    }
  }

  /// Parsea fecha_trabajo "DD/MM/YY", "DD.MM.YYYY", "YYYY-MM-DD", "DD-MM-YYYY" → [dia, mes, anno]
  List<String>? _partirFecha(String fechaStr) {
    final s = fechaStr.trim();
    final isoMatch = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    if (isoMatch != null) {
      return [isoMatch.group(3)!, isoMatch.group(2)!, isoMatch.group(1)!];
    }
    final dmyMatch = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})$').firstMatch(s);
    if (dmyMatch != null) {
      return [dmyMatch.group(1)!, dmyMatch.group(2)!, dmyMatch.group(3)!];
    }
    final normalizada = s.replaceAll('.', '/');
    final partes = normalizada.split('/');
    if (partes.length != 3) return null;
    return partes;
  }

  /// Normaliza columna `red` de calidad_por_red a HFC, FTTH o RED_NEUTRA.
  String _normalizarRed(String? red) {
    final r = (red?.toString().trim() ?? '').toUpperCase();
    if (r.contains('HFC') || r == 'CHFC') return 'HFC';
    if (r.contains('FTTH') || r == 'CFTT' || r.contains('GPON')) return 'FTTH';
    if (r.contains('NTT') || r == 'NFTT' || r.contains('NEUTR')) return 'RED_NEUTRA';
    return r.isNotEmpty ? r : 'RED_NEUTRA';
  }

  /// Convierte periodo MM-YYYY ↔ YYYY-MM (algunas tablas usan uno u otro).
  String _periodoAlternativo(String periodo) {
    final p = periodo.split('-');
    if (p.length != 2) return periodo;
    if (p[0].length == 4) return '${p[1]}-${p[0]}'; // YYYY-MM → MM-YYYY
    return '${p[1]}-${p[0]}'; // MM-YYYY → YYYY-MM
  }

  /// Mes de medición (1–12) desde período "MM-YYYY" o "YYYY-MM".
  int getMesMedicion(String periodo) => _mesAnnoPeriodo(periodo).$1;

  /// Mes y año de medición (acepta MM-YYYY o YYYY-MM).
  (int mes, int anno) parseMesAnnoMedicion(String periodo) =>
      _mesAnnoPeriodo(periodo);

  /// Mes y año del período sin importar si viene "MM-YYYY" o "YYYY-MM".
  (int mes, int anno) _mesAnnoPeriodo(String periodo) {
    final p = periodo.split('-');
    if (p.length != 2) return (0, 0);
    if (p[0].length == 4) {
      return (int.tryParse(p[1]) ?? 0, int.tryParse(p[0]) ?? 0);
    }
    return (int.tryParse(p[0]) ?? 0, int.tryParse(p[1]) ?? 0);
  }

  /// Variantes de RUT para calidad (incluye sin guión vía ProduccionService.rutVariantes).
  static List<String> _rutVariantesCalidad(String rut) =>
      ProduccionService.rutVariantes(rut);

  /// Campo de red/tecnología en fila de calidad_api_script (varía según script).
  String _campoRedFila(Map<String, dynamic> o) {
    final a = o['tipo_red']?.toString().trim();
    if (a != null && a.isNotEmpty) return a;
    final b = o['red']?.toString().trim();
    if (b != null && b.isNotEmpty) return b;
    final c = o['tipo_de_red']?.toString().trim();
    if (c != null && c.isNotEmpty) return c;
    return o['area_derivacion']?.toString().trim() ?? '';
  }

  /// Cuando `calidad_por_red` no tiene filas, arma desglose por tecnología desde calidad_api_script.
  Future<Map<String, dynamic>?> _calidadPorTecnologiaDesdeApiScript(
    String rut,
    String periodo,
  ) async {
    try {
      final variantes = _rutVariantesCalidad(rut);
      if (variantes.isEmpty) return null;

      List<Map<String, dynamic>> todas = [];
      for (final per in {periodo, _periodoAlternativo(periodo)}) {
        try {
          final resp = await _supabase
              .from('calidad_api_script')
              .select()
              .inFilter('rut_o_bucket', variantes)
              .eq('periodo', per)
              .limit(3000);
          todas.addAll(List<Map<String, dynamic>>.from(resp as List));
        } catch (_) {}
      }
      if (todas.isEmpty) return null;

      // Deduplicar por orden + fecha si existe
      final visto = <String>{};
      final unicas = <Map<String, dynamic>>[];
      for (final o in todas) {
        final k = '${o['orden_de_trabajo']}|${o['fecha']}|${o['periodo']}';
        if (visto.add(k)) unicas.add(o);
      }

      final acumPorTec = <String, Map<String, int>>{};
      for (final o in unicas) {
        final tec = _normalizarRed(_campoRedFila(o));
        acumPorTec.putIfAbsent(tec, () => {'completadas': 0, 'reiterados': 0});
        if (o['estado']?.toString() == 'Completado') {
          acumPorTec[tec]!['completadas'] = acumPorTec[tec]!['completadas']! + 1;
        }
        if (_esReiterado(o['es_reiterado'])) {
          acumPorTec[tec]!['reiterados'] = acumPorTec[tec]!['reiterados']! + 1;
        }
      }

      acumPorTec.removeWhere((_, v) => v['completadas']! == 0 && v['reiterados']! == 0);
      if (acumPorTec.isEmpty) return null;

      int totalCompletadas = 0;
      int totalReiterados = 0;
      final porTecnologia = <Map<String, dynamic>>[];
      for (final e in acumPorTec.entries) {
        final comp = e.value['completadas']!;
        final reit = e.value['reiterados']!;
        if (comp == 0) continue;
        totalCompletadas += comp;
        totalReiterados += reit;
        porTecnologia.add({
          'tecnologia': e.key,
          'reiterados': reit,
          'completadas': comp,
          'porcentaje_reiteracion': comp > 0 ? reit / comp * 100 : 0.0,
        });
      }
      if (totalCompletadas == 0) return null;

      final detalle =
          unicas.where((o) => _esReiterado(o['es_reiterado'])).toList();

      print(
          '📋 [Calidad] por_tecnología vía calidad_api_script periodo=$periodo techs=${porTecnologia.length}');

      return {
        'periodo': periodo,
        'total_completadas': totalCompletadas,
        'total_reiterados': totalReiterados,
        'porcentaje_reiteracion':
            totalCompletadas > 0 ? totalReiterados / totalCompletadas * 100 : 0.0,
        'por_tecnologia': porTecnologia,
        'detalle': detalle,
        'origen_por_tecnologia': 'api_script',
      };
    } catch (e) {
      print('⚠️ [Calidad] _calidadPorTecnologiaDesdeApiScript: $e');
      return null;
    }
  }

  /// Calidad por período desglosada por tecnología (para contrato antiguo).
  /// Usa tabla calidad_por_red: rut_o_bucket, periodo, red, total_ordenes, reiteradas, pct_reiteracion.
  Future<Map<String, dynamic>?> obtenerCalidadPorPeriodoPorTecnologia(
    String rut,
    String periodo,
  ) async {
    try {
      final variantesRut = ProduccionService.rutVariantes(rut);
      List<dynamic> filas = [];
      if (variantesRut.isNotEmpty) {
        filas = await _supabase
            .from('calidad_por_red')
            .select('red, total_ordenes, reiteradas, pct_reiteracion')
            .inFilter('rut_o_bucket', variantesRut)
            .eq('periodo', periodo)
            .limit(100) as List;

        if (filas.isEmpty) {
          final periodoAlt = _periodoAlternativo(periodo);
          filas = await _supabase
              .from('calidad_por_red')
              .select('red, total_ordenes, reiteradas, pct_reiteracion')
              .inFilter('rut_o_bucket', variantesRut)
              .eq('periodo', periodoAlt)
              .limit(100) as List;
          if (filas.isNotEmpty) {
            print('📋 [Calidad] calidad_por_red usó periodo alternativo: $periodoAlt (original: $periodo)');
          }
        }
      }

      if (filas.isEmpty) {
        print('⚠️ [Calidad] calidad_por_red sin datos: rut=$rut periodo=$periodo — intentando calidad_api_script');
        return await _calidadPorTecnologiaDesdeApiScript(rut, periodo);
      }

      final acumPorTec = <String, Map<String, dynamic>>{};

      for (var row in filas) {
        final red = row['red']?.toString() ?? '';
        final totalOrdenes = (row['total_ordenes'] as num?)?.toInt() ?? 0;
        final reiteradas = (row['reiteradas'] as num?)?.toInt() ?? 0;

        if (totalOrdenes == 0) continue;

        final tecno = _normalizarRed(red);
        if (!acumPorTec.containsKey(tecno)) {
          acumPorTec[tecno] = {'reiterados': 0, 'completadas': 0};
        }
        acumPorTec[tecno]!['reiterados'] = (acumPorTec[tecno]!['reiterados'] as int) + reiteradas;
        acumPorTec[tecno]!['completadas'] = (acumPorTec[tecno]!['completadas'] as int) + totalOrdenes;
      }

      int totalCompletadas = 0;
      int totalReiterados = 0;
      final porTecnologia = <Map<String, dynamic>>[];

      for (final entry in acumPorTec.entries) {
        final tecno = entry.key;
        final reiterados = entry.value['reiterados'] as int;
        final completadas = entry.value['completadas'] as int;
        final pct = completadas > 0 ? reiterados / completadas * 100 : 0.0;
        totalCompletadas += completadas;
        totalReiterados += reiterados;
        porTecnologia.add({
          'tecnologia': tecno,
          'reiterados': reiterados,
          'completadas': completadas,
          'porcentaje_reiteracion': pct,
        });
      }

      if (totalCompletadas == 0) return null;

      // Detalle reiterados (ambos formatos de período)
      List<Map<String, dynamic>> detalle = [];
      try {
        final variantes = _rutVariantesCalidad(rut);
        if (variantes.isNotEmpty) {
          for (final per in {periodo, _periodoAlternativo(periodo)}) {
            try {
              final resp = await _supabase
                  .from('calidad_api_script')
                  .select()
                  .inFilter('rut_o_bucket', variantes)
                  .eq('periodo', per)
                  .limit(500);
              final ordenes = List<Map<String, dynamic>>.from(resp as List);
              detalle = ordenes.where((o) => _esReiterado(o['es_reiterado'])).toList();
              if (detalle.isNotEmpty) break;
            } catch (_) {}
          }
        }
      } catch (_) {}

      return {
        'periodo': periodo,
        'total_completadas': totalCompletadas,
        'total_reiterados': totalReiterados,
        'porcentaje_reiteracion': totalCompletadas > 0 ? totalReiterados / totalCompletadas * 100 : 0.0,
        'por_tecnologia': porTecnologia,
        'detalle': detalle,
      };
    } catch (e) {
      print('❌ [CalidadTraza] Error calidad por tecnologia (calidad_por_red): $e');
      return null;
    }
  }

  /// Total de órdenes completadas en produccion para rut y mes.
  /// periodo puede ser "MM-YYYY" o "YYYY-MM". Usa misma lógica que Producción.
  Future<int> _obtenerTotalProduccionMes(String rut, String periodo) async {
    try {
      final partes = periodo.split('-');
      if (partes.length != 2) return 0;
      int mesConsulta;
      int annoConsulta;
      if (partes[0].length == 4) {
        annoConsulta = int.tryParse(partes[0]) ?? 0;
        mesConsulta = int.tryParse(partes[1]) ?? 0;
      } else {
        mesConsulta = int.tryParse(partes[0]) ?? 0;
        annoConsulta = int.tryParse(partes[1]) ?? 0;
      }
      if (mesConsulta < 1 || mesConsulta > 12) return 0;

      // 1. Por RUT (múltiples formatos: 12345678-9, 12.345.678-9)
      final variantesRut = ProduccionService.rutVariantes(rut);
      List<dynamic> respRut = [];
      if (variantesRut.isNotEmpty) {
        respRut = await _supabase
            .from('produccion')
            .select('orden_trabajo, fecha_trabajo, estado, area_derivacion')
            .inFilter('rut_tecnico', variantesRut)
            .limit(10000) as List;
      }

      // 2. Por nombre (datos legacy; ilike = case-insensitive)
      String? nombreTecnico;
      try {
        final tecnico = await _supabase
            .from('tecnicos_traza_zc')
            .select('nombre_completo')
            .eq('rut', rut)
            .maybeSingle();
        nombreTecnico = tecnico?['nombre_completo']?.toString()?.trim();
      } catch (_) {}

      List<dynamic> respNombre = [];
      if (nombreTecnico != null && nombreTecnico.isNotEmpty) {
        try {
          respNombre = await _supabase
              .from('produccion')
              .select('orden_trabajo, fecha_trabajo, estado, area_derivacion')
              .ilike('tecnico', nombreTecnico)
              .limit(10000) as List;
        } catch (_) {
          respNombre = await _supabase
              .from('produccion')
              .select('orden_trabajo, fecha_trabajo, estado, area_derivacion')
              .eq('tecnico', nombreTecnico)
              .limit(10000) as List;
        }
      }

      // 3. Combinar, ordenar (Completado primero), deduplicar y filtrar por mes
      final combinadas = [...(respRut as List), ...respNombre];
      combinadas.sort((a, b) => ProduccionService.prioridadEstado(a).compareTo(ProduccionService.prioridadEstado(b)));

      final Map<String, dynamic> ordenesMap = {};
      for (var orden in combinadas) {
        final fechaStr = orden['fecha_trabajo']?.toString() ?? '';
        final partesFecha = _partirFecha(fechaStr);
        if (partesFecha == null) continue;
        var mesOrden = int.tryParse(partesFecha[1]) ?? 0;
        var annoOrden = int.tryParse(partesFecha[2]) ?? 0;
        if (annoOrden < 100) annoOrden = 2000 + annoOrden;
        if (mesOrden != mesConsulta || annoOrden != annoConsulta) continue;

        final ordenId = (orden['orden_trabajo']?.toString() ?? '').trim();
        if (ordenId.isEmpty) continue;
        final key = '$ordenId-$fechaStr';
        if (!ordenesMap.containsKey(key)) ordenesMap[key] = orden;
      }

      return ordenesMap.values.where((r) => _cuentaComoProduccion(r)).length;
    } catch (e) {
      print('❌ [CalidadTraza] Error total produccion: $e');
      return 0;
    }
  }

  /// Ranking de todos los técnicos para el período.
  /// Retorna mapa con 'ranking' (lista ordenada por porcentaje asc) y 'totalTecnicos'.
  Future<Map<String, dynamic>> obtenerRankingPorPeriodo(String periodo) async {
    try {
      // Query 1: todas las completadas del período
      final respComp = await _supabase
          .from('calidad_api_script')
          .select('rut_o_bucket, tecnico')
          .eq('periodo', periodo)
          .eq('estado', 'Completado')
          .limit(10000);

      // Query 2: todos los reiterados del período
      // (traer todos y filtrar en cliente: es_reiterado puede ser true o "SI")
      final respReit = await _supabase
          .from('calidad_api_script')
          .select('rut_o_bucket, tecnico, es_reiterado, reiterada_valida')
          .eq('periodo', periodo)
          .limit(10000);

      final completadas = List<Map<String, dynamic>>.from(respComp as List);
      final reiterados = (List<Map<String, dynamic>>.from(respReit as List))
          .where((o) => _esReiterado(o['es_reiterado']))
          .toList();

      print('📊 [CalidadRanking] periodo=$periodo | completadas=${completadas.length} | es_reiterado_true=${reiterados.length}');
      if (reiterados.isNotEmpty) {
        print('📊 [CalidadRanking] Primer reiterado: rut=${reiterados.first['rut_o_bucket']} es_reit=${reiterados.first['es_reiterado']} valida=${reiterados.first['reiterada_valida']}');
      }

      // Agrupar por técnico
      final Map<String, Map<String, dynamic>> porTecnico = {};

      for (final o in completadas) {
        final rut = o['rut_o_bucket']?.toString() ?? '';
        if (rut.isEmpty) continue;
        porTecnico.putIfAbsent(rut, () => {
          'rut_tecnico': rut,
          'tecnico': o['tecnico']?.toString() ?? '',
          'completadas': 0,
          'reiterados': 0,
        });
        porTecnico[rut]!['completadas'] =
            (porTecnico[rut]!['completadas'] as int) + 1;
      }

      for (final o in reiterados) {
        final rut = o['rut_o_bucket']?.toString() ?? '';
        if (rut.isEmpty) continue;
        // Si el técnico tiene reiterados pero no completadas en este período, lo incluimos
        porTecnico.putIfAbsent(rut, () => {
          'rut_tecnico': rut,
          'tecnico': o['tecnico']?.toString() ?? '',
          'completadas': 0,
          'reiterados': 0,
        });
        porTecnico[rut]!['reiterados'] =
            (porTecnico[rut]!['reiterados'] as int) + 1;
      }

      // Calcular porcentaje
      final ranking = porTecnico.values.map((t) {
        final completadas = t['completadas'] as int;
        final reiterados = t['reiterados'] as int;
        final pct = completadas > 0 ? reiterados / completadas * 100 : 0.0;
        return {
          ...t,
          'porcentaje_reiteracion': pct,
          'total_reiterados': reiterados,
          'total_completadas': completadas,
        };
      }).toList();

      // Solo técnicos con órdenes completadas (sin datos no participan en ranking)
      final rankingFiltrado = ranking
          .where((t) => (t['total_completadas'] as int) > 0)
          .toList();

      // Ordenar por porcentaje ascendente (menor % = mejor calidad)
      rankingFiltrado.sort((a, b) => (a['porcentaje_reiteracion'] as double)
          .compareTo(b['porcentaje_reiteracion'] as double));

      for (int i = 0; i < rankingFiltrado.length; i++) {
        rankingFiltrado[i]['posicion'] = i + 1;
      }

      return {
        'ranking': rankingFiltrado,
        'totalTecnicos': rankingFiltrado.length,
      };
    } catch (e) {
      print('❌ [CalidadTraza] Error obteniendo ranking: $e');
      return {'ranking': [], 'totalTecnicos': 0};
    }
  }

  /// Posición del técnico en el ranking del período.
  Future<Map<String, dynamic>> obtenerPosicionEnRanking(
    String rut,
    String periodo,
  ) async {
    final data = await obtenerRankingPorPeriodo(periodo);
    final ranking = List<Map<String, dynamic>>.from(data['ranking'] as List);

    Map<String, dynamic>? encontrado;
    for (final t in ranking) {
      if (t['rut_tecnico'] == rut) {
        encontrado = t;
        break;
      }
    }

    return {
      'posicion': encontrado?['posicion'] ?? 0,
      'totalTecnicos': ranking.length,
      'top10': ranking,
    };
  }

  // ── Helpers de fecha y período ────────────────────────────────────────────

  /// Parsea fecha en formato "DD/MM/YY" o "DD/MM/YYYY"
  DateTime? _parseFecha(String fecha) {
    if (fecha.isEmpty) return null;
    try {
      final p = fecha.split('/');
      if (p.length == 3) {
        final dia = int.parse(p[0]);
        final mes = int.parse(p[1]);
        final anno = p[2].length == 2 ? 2000 + int.parse(p[2]) : int.parse(p[2]);
        return DateTime(anno, mes, dia);
      }
    } catch (_) {}
    return null;
  }

  /// Obtiene tipo_contrato del técnico (nuevo/CN o antiguo/CA).
  /// Usa rutVariantes para coincidir con el formato en tecnicos_traza_zc.
  /// [prefs] opcional: SharedPreferences para fallback si BD no tiene dato.
  Future<String> obtenerTipoContrato(String rut, {dynamic prefs}) async {
    try {
      final variantes = ProduccionService.rutVariantes(rut);
      if (variantes.isEmpty) return _tipoContratoDesdePrefs(prefs);

      dynamic r;
      try {
        final list = await _supabase
            .from('tecnicos_traza_zc')
            .select('tipo_contrato')
            .inFilter('rut', variantes)
            .limit(1) as List;
        r = list.isNotEmpty ? list.first : null;
      } catch (_) {
        for (final v in variantes) {
          r = await _supabase
              .from('tecnicos_traza_zc')
              .select('tipo_contrato')
              .eq('rut', v)
              .maybeSingle();
          if (r != null) break;
        }
      }

      final t = r?['tipo_contrato']?.toString().trim().toUpperCase();
      if (t != null && t.isNotEmpty) {
        print('📋 [Calidad] tipo_contrato desde tecnicos_traza_zc: $t');
        if (t == 'CA' || t == 'ANTIGUO' || t.contains('ANTIG')) return 'antiguo';
        return 'nuevo';
      }

      final desdePrefs = _tipoContratoDesdePrefs(prefs);
      print('📋 [Calidad] tipo_contrato no en BD, usando: $desdePrefs');
      return desdePrefs;
    } catch (e) {
      print('⚠️ [Calidad] Error obtenerTipoContrato: $e');
      return _tipoContratoDesdePrefs(prefs);
    }
  }

  String _tipoContratoDesdePrefs(dynamic prefs) {
    if (prefs == null) return 'nuevo';
    try {
      final v = prefs.getString('tipo_contrato')?.trim().toUpperCase() ?? '';
      if (v.contains('ANTIG') || v == 'CA') return 'antiguo';
      if (v.contains('NUEV') || v == 'CN') return 'nuevo';
    } catch (_) {}
    return 'nuevo';
  }

  /// Nombre del bono desde período "MM-YYYY" (mes de trabajo).
  /// periodo = mes de trabajo → bono = mes siguiente.
  ///   "01-2026" = trabajo enero → BONO FEB
  ///   "02-2026" = trabajo febrero → BONO MAR
  String getNombreBono(String periodo) {
    try {
      final (mesTrabajo, anno) = _mesAnnoPeriodo(periodo);
      if (mesTrabajo < 1 || mesTrabajo > 12 || anno < 2000) return '';
      final mesBono = DateTime(anno, mesTrabajo + 1, 1);
      const meses = [
        '', 'ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN',
        'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC'
      ];
      return meses[mesBono.month];
    } catch (_) {
      return '';
    }
  }

  /// Info de texto del período para mostrar en la card.
  /// periodo "02-2026" = trabajo febrero → BONO MAR
  Map<String, String> getInfoPeriodo(String periodo) {
    try {
      final (mesTrabajo, anno) = _mesAnnoPeriodo(periodo);
      if (mesTrabajo < 1 || mesTrabajo > 12) {
        return {'periodo_texto': '', 'fin_garantia_texto': ''};
      }

      // periodo = mes de trabajo
      final ultimoDiaMes = DateTime(anno, mesTrabajo + 1, 0).day;
      final mesBono = DateTime(anno, mesTrabajo + 1, 1);
      final ultimoDiaGarantia = DateTime(anno, mesTrabajo + 2, 0).day;

      const mesesLargos = [
        '', 'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
        'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
      ];

      final mesTrabajoNombre = mesesLargos[mesTrabajo];
      final mesBonoNombre = mesesLargos[mesBono.month];

      return {
        'periodo_texto':
            '1 de $mesTrabajoNombre al $ultimoDiaMes de $mesTrabajoNombre',
        'fin_garantia_texto':
            'Fin de garantías el $ultimoDiaGarantia de $mesBonoNombre',
      };
    } catch (_) {
      return {'periodo_texto': '', 'fin_garantia_texto': ''};
    }
  }

  /// Formatea fecha "DD/MM/YY" → "DD/MM"
  String formatearFecha(String fecha) {
    try {
      final p = fecha.split('/');
      if (p.length == 3) return '${p[0]}/${p[1]}';
    } catch (_) {}
    return fecha;
  }
}
