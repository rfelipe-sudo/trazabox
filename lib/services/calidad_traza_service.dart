import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio de calidad para TrazaBox.
/// Fuente de datos: tabla `calidad_api_script` en Supabase.
///
/// Lógica de períodos (diferente a agente_desconexiones):
///   - Trabajo: del 1 al último día del mes anterior al BONO
///   - Garantía: vence el último día del mes del BONO
///   - Ejemplo: BONO 02-2026 (FEB) → trabajo 1-31 ENE, garantía hasta 28 FEB
///
/// Formato del campo `periodo` en BD: "MM-YYYY" (ej: "02-2026")
class CalidadTrazaService {
  static final CalidadTrazaService _instance = CalidadTrazaService._internal();
  factory CalidadTrazaService() => _instance;
  CalidadTrazaService._internal();

  final _supabase = Supabase.instance.client;

  // ── Helpers de período ────────────────────────────────────────────────────

  String _formatPeriodo(int mes, int anno) =>
      '${mes.toString().padLeft(2, '0')}-$anno';

  /// Período CERRADO: garantía ya venció (mes anterior al actual).
  /// Hoy 6 MAR → 02-2026 (FEB) cuya garantía expiró el 28 FEB → CERRADO
  String getPeriodoCerrado() {
    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1, 1);
    return _formatPeriodo(prev.month, prev.year);
  }

  /// Período MIDIENDO: garantía aún vigente (mes actual).
  /// Hoy 6 MAR → 03-2026 (MAR) cuya garantía expira el 31 MAR → MIDIENDO
  String getPeriodoMidiendo() {
    final now = DateTime.now();
    return _formatPeriodo(now.month, now.year);
  }

  /// Período PRÓXIMO: el siguiente bono que aún está en trabajo (no hay datos todavía).
  /// Hoy 6 MAR → 04-2026 (ABR) cuyo trabajo es todo marzo → SIN DATOS AÚN
  String getPeriodoProximo() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month + 1, 1);
    return _formatPeriodo(next.month, next.year);
  }

  // ── Consulta principal ────────────────────────────────────────────────────

  /// Obtiene todas las órdenes del técnico para el período dado y calcula métricas.
  /// Retorna un mapa con:
  ///   periodo, total_completadas, total_reiterados,
  ///   porcentaje_reiteracion, promedio_dias, detalle (lista de reiterados válidos)
  Future<Map<String, dynamic>?> obtenerCalidadPorPeriodo(
    String rut,
    String periodo,
  ) async {
    try {
      final response = await _supabase
          .from('calidad_api_script')
          .select()
          .eq('rut_o_bucket', rut)
          .eq('periodo', periodo);

      final ordenes = List<Map<String, dynamic>>.from(response as List);

      if (ordenes.isEmpty) return null;

      final completadas = ordenes
          .where((o) => o['estado']?.toString() == 'Completado')
          .length;

      final reiteradosValidos = ordenes.where((o) {
        final esReit = o['es_reiterado'];
        // Contar si es_reiterado está marcado, sin exigir reiterada_valida
        return esReit == true || esReit == 1 || esReit?.toString() == 'true';
      }).toList();

      final porcentaje = completadas > 0
          ? reiteradosValidos.length / completadas * 100
          : 0.0;

      // Promedio de días entre fecha original y fecha reiterada
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
        'total_completadas': completadas,
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

      // Query 2: todos los reiterados del período (cualquier estado con es_reiterado=true)
      final respReit = await _supabase
          .from('calidad_api_script')
          .select('rut_o_bucket, tecnico, es_reiterado, reiterada_valida')
          .eq('periodo', periodo)
          .eq('es_reiterado', true)
          .limit(10000);

      final completadas = List<Map<String, dynamic>>.from(respComp as List);
      final reiterados  = List<Map<String, dynamic>>.from(respReit as List);

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

  /// Nombre del bono desde período "MM-YYYY".
  /// El campo `periodo` en calidad_api_script ES el mes del bono:
  ///   "02-2026" = BONO FEB (trabajo en enero, garantía hasta feb)
  ///   "03-2026" = BONO MAR (trabajo en febrero, garantía hasta mar)
  String getNombreBono(String periodo) {
    try {
      final mes = int.parse(periodo.split('-')[0]);
      const meses = [
        '', 'ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN',
        'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC'
      ];
      return meses[mes];
    } catch (_) {
      return '';
    }
  }

  /// Info de texto del período para mostrar en la card.
  /// periodo "03-2026" = BONO MAR → trabajo 1-28 feb, garantía hasta 31 mar
  Map<String, String> getInfoPeriodo(String periodo) {
    try {
      final partes = periodo.split('-');
      final mesBono = int.parse(partes[0]);   // mes del BONO (garantía)
      final annoBono = int.parse(partes[1]);

      // Mes de trabajo = mes anterior al bono
      final fechaTrabajoInicio = DateTime(annoBono, mesBono - 1, 1);
      final fechaTrabajoFin = DateTime(annoBono, mesBono, 0); // último día del mes anterior

      // Último día del mes del bono (fin de garantía)
      final ultimoDiaGarantia = DateTime(annoBono, mesBono + 1, 0).day;

      const mesesLargos = [
        '', 'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
        'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
      ];

      final mesTrabajoNombre = mesesLargos[fechaTrabajoInicio.month];
      final mesBonoNombre = mesesLargos[mesBono];

      return {
        'periodo_texto':
            '1 de $mesTrabajoNombre al ${fechaTrabajoFin.day} de $mesTrabajoNombre',
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
