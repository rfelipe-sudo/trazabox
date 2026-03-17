// ═══════════════════════════════════════════════════════════════════
// PATCH: Reemplazar método obtenerMetricasTiempo() en produccion_service.dart
// ═══════════════════════════════════════════════════════════════════
//
// Instrucciones:
// 1. Abrir: C:\Users\Usuario\trazabox\lib\services\produccion_service.dart
// 2. Buscar el método obtenerMetricasTiempo() (línea ~1504)
// 3. Reemplazar TODO el método con el código de abajo
//
// ═══════════════════════════════════════════════════════════════════

  /// Obtener métricas de tiempo del técnico en el mes
  /// VERSIÓN SIMPLIFICADA: Usa las vistas v_resumen_tiempos_app y v_tiempos_diarios
  Future<Map<String, dynamic>> obtenerMetricasTiempo(
    String rutTecnico, {
    int? mes,
    int? anno,
  }) async {
    final now = DateTime.now();
    final mesConsulta = mes ?? now.month;
    final annoConsulta = anno ?? now.year;

    print('⏰ [Tiempos] Consultando tiempos para RUT: $rutTecnico, Mes: $mesConsulta, Año: $annoConsulta');

    try {
      // ═════════════════════════════════════════════════════════════
      // PASO 1: Obtener resumen desde v_resumen_tiempos_app
      // ═════════════════════════════════════════════════════════════
      final resumenResponse = await _supabase
          .from('v_resumen_tiempos_app')
          .select()
          .eq('rut_tecnico', rutTecnico)
          .eq('mes', mesConsulta)
          .eq('anio', annoConsulta)
          .maybeSingle();

      if (resumenResponse == null) {
        print('⚠️ [Tiempos] No hay datos en v_resumen_tiempos_app');
        return _metricasTiempoVacias();
      }

      // ═════════════════════════════════════════════════════════════
      // PASO 2: Obtener detalle diario desde v_tiempos_diarios
      // ═════════════════════════════════════════════════════════════
      final detalleDiarioResponse = await _supabase
          .from('v_tiempos_diarios')
          .select()
          .eq('rut_tecnico', rutTecnico)
          .filter('fecha_completa', 'gte', '$annoConsulta-${mesConsulta.toString().padLeft(2, '0')}-01')
          .filter('fecha_completa', 'lt', '$annoConsulta-${(mesConsulta % 12 + 1).toString().padLeft(2, '0')}-01')
          .order('fecha_completa', ascending: false);

      final detalleDiario = List<Map<String, dynamic>>.from(detalleDiarioResponse as List);

      print('✅ [Tiempos] Resumen: ${resumenResponse}');
      print('✅ [Tiempos] ${detalleDiario.length} días con detalle');

      // ═════════════════════════════════════════════════════════════
      // PASO 3: Construir detalleInicioTardio
      // ═════════════════════════════════════════════════════════════
      List<Map<String, dynamic>> detalleInicioTardio = detalleDiario
          .where((dia) => (dia['minutos_inicio_tardio'] as num?)?.toInt() ?? 0 > 0)
          .map((dia) {
            final esSabado = (dia['dia_semana'] as num?)?.toInt() == 6;
            return {
              'fecha': dia['fecha_trabajo']?.toString() ?? '',
              'horaInicio': dia['primera_orden_hora']?.toString() ?? '00:00',
              'retraso': (dia['minutos_inicio_tardio'] as num?)?.toInt() ?? 0,
              'esSabado': esSabado,
            };
          }).toList();

      // ═════════════════════════════════════════════════════════════
      // PASO 4: Construir detalleHorasExtras (agrupado por semana)
      // ═════════════════════════════════════════════════════════════
      Map<int, List<Map<String, dynamic>>> porSemana = {};
      
      for (final dia in detalleDiario) {
        final minutosExtra = (dia['minutos_hora_extra'] as num?)?.toInt() ?? 0;
        if (minutosExtra == 0) continue;

        // Parsear fecha para determinar semana
        final fechaStr = dia['fecha_trabajo']?.toString() ?? '';
        final partes = fechaStr.split('/');
        if (partes.length != 3) continue;

        final diaNum = int.tryParse(partes[0]) ?? 0;
        
        // Determinar semana (1-7, 8-14, 15-21, 22-28, 29-31)
        int semanaNum = ((diaNum - 1) ~/ 7) + 1;
        if (semanaNum > 5) semanaNum = 5;

        porSemana.putIfAbsent(semanaNum, () => []).add({
          'fecha': fechaStr,
          'horaFin': dia['ultima_orden_hora']?.toString() ?? '',
          'minutos': minutosExtra,
        });
      }

      List<Map<String, dynamic>> detalleHorasExtras = [];
      
      // Agregar encabezados de semana y sus días
      porSemana.keys.toList()..sort();
      for (final semanaNum in porSemana.keys.toList()..sort()) {
        final dias = porSemana[semanaNum]!;
        final totalSemana = dias.fold<int>(0, (sum, dia) => sum + (dia['minutos'] as int));

        // Encabezado de semana
        detalleHorasExtras.add({
          'tipo': 'semana',
          'semana': semanaNum,
          'total': totalSemana,
          'dias': dias.length,
        });

        // Días de la semana
        for (final dia in dias) {
          detalleHorasExtras.add({
            'tipo': 'dia',
            'fecha': dia['fecha'],
            'horaFin': dia['horaFin'],
            'minutos': dia['minutos'],
          });
        }
      }

      // ═════════════════════════════════════════════════════════════
      // PASO 5: Calcular tiempos de trabajo y trayecto (estimados)
      // ═════════════════════════════════════════════════════════════
      // Nota: Estos cálculos son aproximados ya que la nueva vista
      // se enfoca en inicio tardío y horas extras.
      
      final ordenes = await _supabase
          .from('produccion')
          .select('duracion_min, hora_inicio, hora_fin')
          .eq('rut_tecnico', rutTecnico)
          .eq('estado', 'Completado');

      final ordenesList = List<Map<String, dynamic>>.from(ordenes as List);
      
      // Filtrar por mes
      final ordenesMes = ordenesList.where((orden) {
        final fechaStr = orden['fecha_trabajo']?.toString() ?? '';
        final partes = fechaStr.split('/');
        if (partes.length != 3) return false;
        
        final mesOrden = int.tryParse(partes[1]) ?? 0;
        var annoOrden = int.tryParse(partes[2]) ?? 0;
        if (annoOrden < 100) annoOrden = 2000 + annoOrden;
        
        return mesOrden == mesConsulta && annoOrden == annoConsulta;
      }).toList();

      int tiempoTrabajoTotal = 0;
      for (var orden in ordenesMes) {
        tiempoTrabajoTotal += (orden['duracion_min'] as num?)?.toInt() ?? 0;
      }

      // Tiempo de trayecto estimado (20% del tiempo de trabajo)
      int tiempoTrayectoTotal = (tiempoTrabajoTotal * 0.2).round();

      // Tiempo sin actividad (tiempo total del mes - trabajo - trayecto)
      final diasMes = DateTime(annoConsulta, mesConsulta + 1, 0).day;
      final diasTrabajados = (resumenResponse['dias_trabajados'] as num?)?.toInt() ?? 0;
      final tiempoTotalMes = diasMes * 24 * 60; // Total de minutos del mes
      final tiempoOcioEsperado = diasTrabajados * 480; // 8 horas por día trabajado
      final tiempoSinActividad = tiempoOcioEsperado - tiempoTrabajoTotal - tiempoTrayectoTotal;

      // ═════════════════════════════════════════════════════════════
      // PASO 6: Construir resultado
      // ═════════════════════════════════════════════════════════════
      return {
        // INICIO TARDÍO
        'tiempoInicioTardio': (resumenResponse['minutos_inicio_tardio'] as num?)?.toInt() ?? 0,
        'detalleInicioTardio': detalleInicioTardio,
        
        // HORAS EXTRAS
        'horasExtrasTotal': (resumenResponse['minutos_hora_extra'] as num?)?.toInt() ?? 0,
        'detalleHorasExtras': detalleHorasExtras,
        
        // TIEMPOS GENERALES (para la barra de distribución)
        'tiempoTrabajoTotal': tiempoTrabajoTotal,
        'tiempoTrayectoTotal': tiempoTrayectoTotal,
        'tiempoSinActividad': tiempoSinActividad.clamp(0, tiempoTotalMes),
        'tiempoFinTemprano': 0, // Ya no se calcula
        'tiempoProductivoEsperado': diasTrabajados * 480, // 8h por día
        
        // ESTADÍSTICAS
        'diasTrabajados': diasTrabajados,
        'diasSemana': diasTrabajados - (resumenResponse['dias_trabajados'] as num?)?.toInt() ?? 0,
        'diasSabado': 0, // TODO: calcular si es necesario
      };
      
    } catch (e, stack) {
      print('❌ [Tiempos] Error al obtener métricas de tiempo: $e');
      print('❌ [Tiempos] Stack: $stack');
      return _metricasTiempoVacias();
    }
  }

  // Método auxiliar sin cambios
  Map<String, dynamic> _metricasTiempoVacias() {
    return {
      'tiempoInicioTardio': 0,
      'tiempoFinTemprano': 0,
      'tiempoTrabajoTotal': 0,
      'tiempoTrayectoTotal': 0,
      'tiempoSinActividad': 0,
      'tiempoProductivoEsperado': 0,
      'diasTrabajados': 0,
      'diasSemana': 0,
      'diasSabado': 0,
      'detalleInicioTardio': [],
      'horasExtrasTotal': 0,
      'detalleHorasExtras': [],
    };
  }

