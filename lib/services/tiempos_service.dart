import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio para gestionar tiempos de trabajo (inicio tardío y horas extras)
class TiemposService {
  static final _supabase = Supabase.instance.client;

  /// Obtiene el resumen de tiempos (inicio tardío + horas extras) de un técnico
  /// para un mes específico
  static Future<Map<String, dynamic>> obtenerResumenTiempos(
    String rutTecnico, {
    int? mes,
    int? anno,
  }) async {
    try {
      final now = DateTime.now();
      final mesConsulta = mes ?? now.month;
      final annoConsulta = anno ?? now.year;

      print('⏰ [Tiempos] Consultando resumen para RUT: $rutTecnico, Mes: $mesConsulta, Año: $annoConsulta');

      final response = await _supabase
          .from('v_resumen_tiempos_app')
          .select()
          .eq('rut_tecnico', rutTecnico)
          .eq('mes', mesConsulta)
          .eq('anio', annoConsulta)
          .maybeSingle();

      if (response == null) {
        print('⚠️ [Tiempos] No hay datos de tiempos para este técnico');
        return {
          'minutos_inicio_tardio': 0,
          'horas_inicio_tardio': 0.0,
          'dias_con_inicio_tardio': 0,
          'minutos_hora_extra': 0,
          'horas_extra': 0.0,
          'dias_con_hora_extra': 0,
          'dias_trabajados': 0,
          'ordenes_totales': 0,
        };
      }

      print('✅ [Tiempos] Datos obtenidos: ${response}');

      return {
        'minutos_inicio_tardio': (response['minutos_inicio_tardio'] as num?)?.toInt() ?? 0,
        'horas_inicio_tardio': (response['horas_inicio_tardio'] as num?)?.toDouble() ?? 0.0,
        'dias_con_inicio_tardio': (response['dias_con_inicio_tardio'] as num?)?.toInt() ?? 0,
        'minutos_hora_extra': (response['minutos_hora_extra'] as num?)?.toInt() ?? 0,
        'horas_extra': (response['horas_extra'] as num?)?.toDouble() ?? 0.0,
        'dias_con_hora_extra': (response['dias_con_hora_extra'] as num?)?.toInt() ?? 0,
        'dias_trabajados': (response['dias_trabajados'] as num?)?.toInt() ?? 0,
        'ordenes_totales': (response['ordenes_totales'] as num?)?.toInt() ?? 0,
      };
    } catch (e, stack) {
      print('❌ [Tiempos] Error al obtener resumen de tiempos: $e');
      print('❌ [Tiempos] Stack: $stack');
      return {
        'minutos_inicio_tardio': 0,
        'horas_inicio_tardio': 0.0,
        'dias_con_inicio_tardio': 0,
        'minutos_hora_extra': 0,
        'horas_extra': 0.0,
        'dias_con_hora_extra': 0,
        'dias_trabajados': 0,
        'ordenes_totales': 0,
      };
    }
  }

  /// Obtiene el detalle diario de tiempos de un técnico para un mes específico
  static Future<List<Map<String, dynamic>>> obtenerDetalleDiario(
    String rutTecnico, {
    int? mes,
    int? anno,
  }) async {
    try {
      final now = DateTime.now();
      final mesConsulta = mes ?? now.month;
      final annoConsulta = anno ?? now.year;

      print('📅 [Tiempos] Consultando detalle diario para RUT: $rutTecnico, Mes: $mesConsulta, Año: $annoConsulta');

      final response = await _supabase
          .from('v_tiempos_diarios')
          .select()
          .eq('rut_tecnico', rutTecnico)
          .filter('fecha_completa', 'gte', '$annoConsulta-${mesConsulta.toString().padLeft(2, '0')}-01')
          .filter('fecha_completa', 'lt', '$annoConsulta-${(mesConsulta + 1).toString().padLeft(2, '0')}-01')
          .order('fecha_completa', ascending: false);

      final detalle = List<Map<String, dynamic>>.from(response as List);

      print('✅ [Tiempos] ${detalle.length} días con datos obtenidos');

      return detalle;
    } catch (e, stack) {
      print('❌ [Tiempos] Error al obtener detalle diario: $e');
      print('❌ [Tiempos] Stack: $stack');
      return [];
    }
  }

  /// Obtiene el ranking de técnicos con más inicio tardío en un mes
  static Future<List<Map<String, dynamic>>> obtenerRankingInicioTardio({
    int? mes,
    int? anno,
    int limit = 10,
  }) async {
    try {
      final now = DateTime.now();
      final mesConsulta = mes ?? now.month;
      final annoConsulta = anno ?? now.year;

      final response = await _supabase
          .from('v_tiempos_mensuales')
          .select()
          .eq('mes', mesConsulta)
          .eq('anio', annoConsulta)
          .filter('horas_inicio_tardio_total', 'gt', 0)
          .order('horas_inicio_tardio_total', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      print('❌ [Tiempos] Error al obtener ranking inicio tardío: $e');
      return [];
    }
  }

  /// Obtiene el ranking de técnicos con más horas extras en un mes
  static Future<List<Map<String, dynamic>>> obtenerRankingHorasExtras({
    int? mes,
    int? anno,
    int limit = 10,
  }) async {
    try {
      final now = DateTime.now();
      final mesConsulta = mes ?? now.month;
      final annoConsulta = anno ?? now.year;

      final response = await _supabase
          .from('v_tiempos_mensuales')
          .select()
          .eq('mes', mesConsulta)
          .eq('anio', annoConsulta)
          .filter('horas_extra_total', 'gt', 0)
          .order('horas_extra_total', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      print('❌ [Tiempos] Error al obtener ranking horas extras: $e');
      return [];
    }
  }
}

