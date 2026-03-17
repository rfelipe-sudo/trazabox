import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';
import '../models/metrica_produccion.dart';
import '../models/equipo_reversa.dart';
import '../models/calidad_tecnico.dart';
import '../utils/feriados_chile.dart';
import 'krp_marcas_service.dart';

class ProduccionService {
  static final ProduccionService _instance = ProduccionService._internal();
  factory ProduccionService() => _instance;
  ProduccionService._internal();

  static const String _endpointSabana = 'https://kepler.sbip.cl/api/v1/toa/get_sabana_metro';
  static const double _rendimientoKmPorLitro = 10.0;
  static const int _precioCombustiblePorLitro = 1200; // Pesos chilenos
  static const int _jornadaMinutos = 540; // 9 horas de jornada

  final _supabase = Supabase.instance.client;
  final _marcasService = KrpMarcasService();

  // ═══════════════════════════════════════════════════════════
  // OBTENER Y PROCESAR SABANA
  // ═══════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> obtenerSabana() async {
    try {
      final response = await http.get(
        Uri.parse(_endpointSabana),
        headers: AppConstants.keplerHeaders,
      );
      
      if (response.statusCode != 200) {
        print('❌ [Produccion] Error HTTP: ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['data'] ?? []);
    } catch (e) {
      print('❌ [Produccion] Error obteniendo sabana: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> obtenerOrdenesTecnico(String tecnicoNombre, {DateTime? fecha}) async {
    final sabana = await obtenerSabana();
    
    final fechaFiltro = fecha ?? DateTime.now();
    final fechaStr = '${fechaFiltro.day.toString().padLeft(2, '0')}/${fechaFiltro.month.toString().padLeft(2, '0')}/${fechaFiltro.year.toString().substring(2)}';
    
    return sabana.where((orden) {
      final tecnico = orden['Técnico']?.toString() ?? '';
      final fechaOrden = orden['Fecha']?.toString() ?? '';
      
      final coincideTecnico = tecnico.toLowerCase().contains(tecnicoNombre.toLowerCase());
      final coincideFecha = fechaOrden == fechaStr;
      
      return coincideTecnico && coincideFecha;
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // CALCULAR MÉTRICAS DEL DÍA
  // ═══════════════════════════════════════════════════════════

  Future<MetricaProduccion?> calcularMetricasDia(String tecnicoRut, String tecnicoNombre, {DateTime? fecha}) async {
    try {
      final ordenes = await obtenerOrdenesTecnico(tecnicoNombre, fecha: fecha);
      
      if (ordenes.isEmpty) {
        print('⚠️ [Produccion] Sin órdenes para $tecnicoNombre');
        return null;
      }

      // Ordenar por hora de inicio
      ordenes.sort((a, b) {
        final inicioA = _parseHora(a['Inicio']?.toString() ?? '00:00');
        final inicioB = _parseHora(b['Inicio']?.toString() ?? '00:00');
        return inicioA.compareTo(inicioB);
      });

      // Calcular tiempos
      int tiempoTrabajo = 0;
      int tiempoTrayecto = 0;
      Map<int, int> ordenesPorHora = {};
      Map<String, int> ordenesPorZona = {};

      for (int i = 0; i < ordenes.length; i++) {
        final orden = ordenes[i];
        final inicio = _parseHora(orden['Inicio']?.toString() ?? '00:00');
        final fin = _parseHora(orden['Fin']?.toString() ?? '00:00');
        
        // Tiempo de trabajo en esta orden
        final duracion = fin - inicio;
        if (duracion > 0) tiempoTrabajo += duracion;

        // Hora pico
        final hora = inicio ~/ 60;
        ordenesPorHora[hora] = (ordenesPorHora[hora] ?? 0) + 1;

        // Zona
        final zona = orden['Zona de trabajo']?.toString() ?? 'Sin zona';
        ordenesPorZona[zona] = (ordenesPorZona[zona] ?? 0) + 1;

        // Tiempo de trayecto (desde fin anterior hasta inicio actual)
        if (i > 0) {
          final finAnterior = _parseHora(ordenes[i - 1]['Fin']?.toString() ?? '00:00');
          final trayecto = inicio - finAnterior;
          if (trayecto > 0 && trayecto < 120) { // Máximo 2 horas de trayecto
            tiempoTrayecto += trayecto;
          }
        }
      }

      // Calcular km recorridos
      double kmTotal = 0;
      for (int i = 1; i < ordenes.length; i++) {
        final lat1 = (ordenes[i - 1]['Coord Y'] as num?)?.toDouble() ?? 0;
        final lon1 = (ordenes[i - 1]['Coord X'] as num?)?.toDouble() ?? 0;
        final lat2 = (ordenes[i]['Coord Y'] as num?)?.toDouble() ?? 0;
        final lon2 = (ordenes[i]['Coord X'] as num?)?.toDouble() ?? 0;
        
        if (lat1 != 0 && lon1 != 0 && lat2 != 0 && lon2 != 0) {
          kmTotal += _calcularDistanciaKm(lat1, lon1, lat2, lon2);
        }
      }

      // Contar estados
      int completadas = 0;
      int quiebres = 0;
      int altas = 0;
      int bajas = 0;
      int reparaciones = 0;

      for (final orden in ordenes) {
        final estado = orden['Estado']?.toString() ?? '';
        final tipo = orden['Tipo de Actividad']?.toString() ?? '';
        final codigoCierre = orden['Código de Cierre']?.toString() ?? '';

        if (estado == 'Completado') {
          completadas++;
          
          if (tipo.toLowerCase().contains('alta')) altas++;
          else if (tipo.toLowerCase().contains('baja')) bajas++;
          else if (tipo.toLowerCase().contains('reparaci')) reparaciones++;
        }

        // Detectar quiebres
        if (_esQuiebre(codigoCierre)) {
          quiebres++;
        }
      }

      // Hora pico
      String? horaPico;
      int maxOrdenes = 0;
      ordenesPorHora.forEach((hora, cantidad) {
        if (cantidad > maxOrdenes) {
          maxOrdenes = cantidad;
          horaPico = '${hora.toString().padLeft(2, '0')}:00';
        }
      });

      // Zona más eficiente
      String? zonaMasEficiente;
      int maxZona = 0;
      ordenesPorZona.forEach((zona, cantidad) {
        if (cantidad > maxZona) {
          maxZona = cantidad;
          zonaMasEficiente = zona;
        }
      });

      // Calcular porcentajes
      final porcentajeProductividad = ordenes.isNotEmpty 
          ? (completadas / ordenes.length) * 100 
          : 0.0;
      final porcentajeQuiebre = ordenes.isNotEmpty 
          ? (quiebres / ordenes.length) * 100 
          : 0.0;
      final productividadVsQuiebre = porcentajeQuiebre > 0 
          ? porcentajeProductividad / porcentajeQuiebre 
          : porcentajeProductividad;

      // Costos
      final combustibleLitros = kmTotal / _rendimientoKmPorLitro;
      final costoCombustible = (combustibleLitros * _precioCombustiblePorLitro).round();

      // Tiempo de ocio
      final tiempoOcio = _jornadaMinutos - tiempoTrabajo - tiempoTrayecto;

      final metrica = MetricaProduccion(
        tecnicoRut: tecnicoRut,
        tecnicoNombre: tecnicoNombre,
        fecha: fecha ?? DateTime.now(),
        tiempoTrabajoMin: tiempoTrabajo,
        tiempoTrayectoMin: tiempoTrayecto,
        tiempoOcioMin: tiempoOcio > 0 ? tiempoOcio : 0,
        tiempoPromedioOrdenMin: completadas > 0 ? tiempoTrabajo ~/ completadas : 0,
        kmRecorridos: kmTotal,
        combustibleLitros: combustibleLitros,
        costoCombustible: costoCombustible,
        ordenesAsignadas: ordenes.length,
        ordenesCompletadas: completadas,
        quiebres: quiebres,
        porcentajeProductividad: porcentajeProductividad,
        porcentajeQuiebre: porcentajeQuiebre,
        productividadVsQuiebre: productividadVsQuiebre,
        altasCompletadas: altas,
        bajasCompletadas: bajas,
        reparacionesCompletadas: reparaciones,
        horaPico: horaPico,
        zonaMasEficiente: zonaMasEficiente,
      );

      // Guardar en Supabase
      await _guardarMetrica(metrica);

      print('✅ [Produccion] Métricas calculadas: ${completadas}/${ordenes.length} órdenes');
      return metrica;

    } catch (e) {
      print('❌ [Produccion] Error calculando métricas: $e');
      return null;
    }
  }

  bool _esQuiebre(String codigoCierre) {
    final quiebres = [
      'sin moradores',
      'cliente ausente',
      'reagenda',
      'no permite',
      'rechaza',
      'cancelada',
      'suspendida',
      'no acceso',
      'dirección errónea',
    ];
    
    final codigoLower = codigoCierre.toLowerCase();
    return quiebres.any((q) => codigoLower.contains(q));
  }

  // ═══════════════════════════════════════════════════════════
  // EXTRAER EQUIPOS EN REVERSA
  // ═══════════════════════════════════════════════════════════

  Future<List<EquipoReversa>> extraerEquiposReversa(String tecnicoRut, String tecnicoNombre, {DateTime? fecha}) async {
    try {
      final ordenes = await obtenerOrdenesTecnico(tecnicoNombre, fecha: fecha);
      final equipos = <EquipoReversa>[];

      for (final orden in ordenes) {
        final tipo = orden['Tipo de Actividad']?.toString() ?? '';
        
        // Solo procesar bajas
        if (!tipo.toLowerCase().contains('baja')) continue;

        final items = orden['Items Orden']?.toString() ?? '';
        final pasos = orden['Pasos']?.toString() ?? '';
        
        // Extraer seriales de los pasos (más confiable)
        final serialesMatch = RegExp(r'Numero de serie\s*:\s*([A-Z0-9]+)', caseSensitive: false)
            .allMatches(pasos);
        
        for (final match in serialesMatch) {
          final serial = match.group(1) ?? '';
          if (serial.isEmpty) continue;

          // Determinar tipo de equipo
          String tipoEquipo = 'Equipo';
          if (pasos.contains('MTA')) tipoEquipo = 'MTA/Router';
          else if (pasos.contains('D-Box')) tipoEquipo = 'D-Box';
          else if (pasos.contains('Extensor')) tipoEquipo = 'Extensor WiFi';
          else if (pasos.contains('CM')) tipoEquipo = 'Cable Modem';

          final equipo = EquipoReversa(
            tecnicoRut: tecnicoRut,
            tecnicoNombre: tecnicoNombre,
            serial: serial,
            tipoEquipo: tipoEquipo,
            ot: orden['Orden de Trabajo']?.toString() ?? '',
            cliente: orden['Cliente']?.toString(),
            direccion: orden['Dirección']?.toString(),
            fechaDesinstalacion: fecha ?? DateTime.now(),
            estado: 'pendiente',
          );

          equipos.add(equipo);
        }
      }

      // Guardar en Supabase
      for (final equipo in equipos) {
        await _guardarEquipoReversa(equipo);
      }

      print('✅ [Reversa] ${equipos.length} equipos extraídos');
      return equipos;

    } catch (e) {
      print('❌ [Reversa] Error extrayendo equipos: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // SUPABASE OPERATIONS
  // ═══════════════════════════════════════════════════════════

  Future<void> _guardarMetrica(MetricaProduccion metrica) async {
    try {
      await _supabase.from('metricas_produccion').upsert(
        metrica.toJson(),
        onConflict: 'tecnico_rut,fecha',
      );
    } catch (e) {
      print('❌ [Produccion] Error guardando métrica: $e');
    }
  }

  Future<void> _guardarEquipoReversa(EquipoReversa equipo) async {
    try {
      await _supabase.from('equipos_reversa').upsert(
        equipo.toJson(),
        onConflict: 'serial,ot',
      );
    } catch (e) {
      print('❌ [Reversa] Error guardando equipo: $e');
    }
  }

  Future<List<EquipoReversa>> obtenerEquiposPendientes(String tecnicoRut) async {
    try {
      final response = await _supabase
          .from('equipos_reversa')
          .select()
          .eq('tecnico_rut', tecnicoRut)
          .eq('estado', 'pendiente')
          .order('fecha_desinstalacion', ascending: false);

      return (response as List)
          .map((json) => EquipoReversa.fromJson(json))
          .toList();
    } catch (e) {
      print('❌ [Reversa] Error obteniendo equipos: $e');
      return [];
    }
  }

  Future<void> marcarEquipoEntregado(String equipoId, String bodegaRecibe) async {
    try {
      await _supabase.from('equipos_reversa').update({
        'estado': 'entregado',
        'fecha_entrega': DateTime.now().toIso8601String().split('T')[0],
        'bodega_recibe': bodegaRecibe,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', equipoId);
      
      print('✅ [Reversa] Equipo marcado como entregado');
    } catch (e) {
      print('❌ [Reversa] Error marcando entregado: $e');
    }
  }

  Future<MetricaProduccion?> obtenerMetricaHoy(String tecnicoRut) async {
    try {
      final hoy = DateTime.now().toIso8601String().split('T')[0];
      
      final response = await _supabase
          .from('metricas_produccion')
          .select()
          .eq('tecnico_rut', tecnicoRut)
          .eq('fecha', hoy)
          .maybeSingle();

      if (response != null) {
        return MetricaProduccion.fromJson(response);
      }
      return null;
    } catch (e) {
      print('❌ [Produccion] Error obteniendo métrica: $e');
      return null;
    }
  }

  Future<List<MetricaProduccion>> obtenerMetricasMes(String tecnicoRut, String mesAnno) async {
    try {
      final response = await _supabase
          .from('metricas_produccion')
          .select()
          .eq('tecnico_rut', tecnicoRut)
          .gte('fecha', '$mesAnno-01')
          .lte('fecha', '$mesAnno-31')
          .order('fecha', ascending: false);

      return (response as List)
          .map((json) => MetricaProduccion.fromJson(json))
          .toList();
    } catch (e) {
      print('❌ [Produccion] Error obteniendo métricas del mes: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // UTILIDADES
  // ═══════════════════════════════════════════════════════════

  int _parseHora(String hora) {
    try {
      final partes = hora.split(':');
      final h = int.parse(partes[0]);
      final m = partes.length > 1 ? int.parse(partes[1]) : 0;
      return h * 60 + m;
    } catch (e) {
      return 0;
    }
  }

  double _calcularDistanciaKm(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // Km
  }

  // ═══════════════════════════════════════════════════════════
  // PROCESAR HISTORIAL COMPLETO
  // ═══════════════════════════════════════════════════════════

  Future<List<MetricaProduccion>> procesarHistorial({
    required String tecnicoRut,
    required String tecnicoNombre,
    required DateTime fechaInicio,
    DateTime? fechaFin,
  }) async {
    final fin = fechaFin ?? DateTime.now();
    final metricas = <MetricaProduccion>[];
    
    print('🔍 [DEBUG] Iniciando procesarHistorial');
    print('🔍 [DEBUG] tecnicoNombre buscado: "$tecnicoNombre"');
    print('🔍 [DEBUG] tecnicoRut: "$tecnicoRut"');
    print('🔍 [DEBUG] Rango: ${fechaInicio.day}/${fechaInicio.month} al ${fin.day}/${fin.month}');
    
    // Obtener toda la sabana una sola vez
    final sabanaCompleta = await obtenerSabana();
    
    print('📋 [DEBUG] Total registros en sabana: ${sabanaCompleta.length}');
    
    if (sabanaCompleta.isEmpty) {
      print('❌ [DEBUG] Sabana vacía!');
      return [];
    }
    
    // DEBUG: Mostrar técnicos CREA únicos en la sabana
    final tecnicosCrea = sabanaCompleta
        .map((o) => o['Técnico']?.toString() ?? '')
        .where((t) => t.contains('_CREA_'))
        .toSet();
    print('👷 [DEBUG] Técnicos CREA en sabana: ${tecnicosCrea.length}');
    for (final t in tecnicosCrea) {
      print('   - "$t"');
    }
    
    // DEBUG: Mostrar fechas únicas
    final fechasUnicas = sabanaCompleta
        .map((o) => o['Fecha']?.toString() ?? 'Sin fecha')
        .toSet();
    print('📅 [DEBUG] Fechas en sabana:');
    for (final f in fechasUnicas) {
      print('   - "$f"');
    }
    
    // Filtrar por técnico (debe contener _CREA_ y el nombre)
    final ordenesDelTecnico = sabanaCompleta.where((orden) {
      final tecnico = orden['Técnico']?.toString() ?? '';
      
      // Solo técnicos CREA
      if (!tecnico.contains('_CREA_')) return false;
      
      // Y que coincida con el nombre buscado
      return tecnico.toLowerCase().contains(tecnicoNombre.toLowerCase());
    }).toList();
    
    print('🎯 [DEBUG] Órdenes que coinciden con "$tecnicoNombre": ${ordenesDelTecnico.length}');
    
    if (ordenesDelTecnico.isEmpty) {
      print('❌ [DEBUG] No se encontraron órdenes para el técnico');
      print('💡 [DEBUG] Verifica que el nombre configurado coincida parcialmente con alguno de los técnicos listados arriba');
      return [];
    }
    
    // Agrupar por fecha
    final Map<String, List<Map<String, dynamic>>> ordenesPorFecha = {};
    for (final orden in ordenesDelTecnico) {
      final fecha = orden['Fecha']?.toString() ?? '';
      ordenesPorFecha.putIfAbsent(fecha, () => []).add(orden);
    }
    
    print('📊 [DEBUG] Órdenes por fecha:');
    ordenesPorFecha.forEach((fecha, ordenes) {
      print('   - $fecha: ${ordenes.length} órdenes');
    });
    
    // Procesar cada fecha
    for (final entry in ordenesPorFecha.entries) {
      final fechaStr = entry.key;
      final ordenesDelDia = entry.value;
      
      // Parsear fecha DD/MM/YY o DD.MM.YY
      final partes = _partirFecha(fechaStr);
      if (partes == null) continue;
      
      final dia = int.tryParse(partes[0]) ?? 0;
      final mes = int.tryParse(partes[1]) ?? 0;
      final anno = 2000 + (int.tryParse(partes[2]) ?? 25);
      
      final fechaParsed = DateTime(anno, mes, dia);
      
      print('⚙️ [DEBUG] Procesando $fechaStr (${ordenesDelDia.length} órdenes)');
      
      // Calcular métricas
      final metrica = await _calcularMetricasDeOrdenes(
        tecnicoRut: tecnicoRut,
        tecnicoNombre: tecnicoNombre,
        fecha: fechaParsed,
        ordenes: ordenesDelDia,
      );
      
      if (metrica != null) {
        metricas.add(metrica);
        print('✅ [DEBUG] Métrica guardada para $fechaStr');
        
        // Extraer equipos
        await _extraerEquiposDeOrdenes(
          tecnicoRut: tecnicoRut,
          tecnicoNombre: tecnicoNombre,
          fecha: fechaParsed,
          ordenes: ordenesDelDia,
        );
      }
    }
    
    print('🏁 [DEBUG] Historial procesado: ${metricas.length} días con métricas');
    return metricas;
  }

  // Método interno para calcular métricas de una lista de órdenes
  Future<MetricaProduccion?> _calcularMetricasDeOrdenes({
    required String tecnicoRut,
    required String tecnicoNombre,
    required DateTime fecha,
    required List<Map<String, dynamic>> ordenes,
  }) async {
    try {
      if (ordenes.isEmpty) return null;

      // Ordenar por hora de inicio
      ordenes.sort((a, b) {
        final inicioA = _parseHora(a['Inicio']?.toString() ?? '00:00');
        final inicioB = _parseHora(b['Inicio']?.toString() ?? '00:00');
        return inicioA.compareTo(inicioB);
      });

      // Calcular tiempos
      int tiempoTrabajo = 0;
      int tiempoTrayecto = 0;
      Map<int, int> ordenesPorHora = {};
      Map<String, int> ordenesPorZona = {};

      for (int i = 0; i < ordenes.length; i++) {
        final orden = ordenes[i];
        final inicio = _parseHora(orden['Inicio']?.toString() ?? '00:00');
        final fin = _parseHora(orden['Fin']?.toString() ?? '00:00');
        
        final duracion = fin - inicio;
        if (duracion > 0) tiempoTrabajo += duracion;

        final hora = inicio ~/ 60;
        ordenesPorHora[hora] = (ordenesPorHora[hora] ?? 0) + 1;

        final zona = orden['Zona de trabajo']?.toString() ?? 'Sin zona';
        ordenesPorZona[zona] = (ordenesPorZona[zona] ?? 0) + 1;

        if (i > 0) {
          final finAnterior = _parseHora(ordenes[i - 1]['Fin']?.toString() ?? '00:00');
          final trayecto = inicio - finAnterior;
          if (trayecto > 0 && trayecto < 120) {
            tiempoTrayecto += trayecto;
          }
        }
      }

      // Calcular km recorridos
      double kmTotal = 0;
      for (int i = 1; i < ordenes.length; i++) {
        final lat1 = (ordenes[i - 1]['Coord Y'] as num?)?.toDouble() ?? 0;
        final lon1 = (ordenes[i - 1]['Coord X'] as num?)?.toDouble() ?? 0;
        final lat2 = (ordenes[i]['Coord Y'] as num?)?.toDouble() ?? 0;
        final lon2 = (ordenes[i]['Coord X'] as num?)?.toDouble() ?? 0;
        
        if (lat1 != 0 && lon1 != 0 && lat2 != 0 && lon2 != 0) {
          kmTotal += _calcularDistanciaKm(lat1, lon1, lat2, lon2);
        }
      }

      // Contar estados
      int completadas = 0;
      int quiebres = 0;
      int altas = 0;
      int bajas = 0;
      int reparaciones = 0;

      for (final orden in ordenes) {
        final estado = orden['Estado']?.toString() ?? '';
        final tipo = orden['Tipo de Actividad']?.toString() ?? '';
        final codigoCierre = orden['Código de Cierre']?.toString() ?? '';

        if (estado == 'Completado') {
          completadas++;
          
          if (tipo.toLowerCase().contains('alta')) altas++;
          else if (tipo.toLowerCase().contains('baja')) bajas++;
          else if (tipo.toLowerCase().contains('reparaci')) reparaciones++;
        }

        if (_esQuiebre(codigoCierre)) {
          quiebres++;
        }
      }

      // Hora pico
      String? horaPico;
      int maxOrdenes = 0;
      ordenesPorHora.forEach((hora, cantidad) {
        if (cantidad > maxOrdenes) {
          maxOrdenes = cantidad;
          horaPico = '${hora.toString().padLeft(2, '0')}:00';
        }
      });

      // Zona más eficiente
      String? zonaMasEficiente;
      int maxZona = 0;
      ordenesPorZona.forEach((zona, cantidad) {
        if (cantidad > maxZona) {
          maxZona = cantidad;
          zonaMasEficiente = zona;
        }
      });

      // Calcular porcentajes
      final porcentajeProductividad = ordenes.isNotEmpty 
          ? (completadas / ordenes.length) * 100 
          : 0.0;
      final porcentajeQuiebre = ordenes.isNotEmpty 
          ? (quiebres / ordenes.length) * 100 
          : 0.0;
      final productividadVsQuiebre = porcentajeQuiebre > 0 
          ? porcentajeProductividad / porcentajeQuiebre 
          : porcentajeProductividad;

      // Costos
      final combustibleLitros = kmTotal / _rendimientoKmPorLitro;
      final costoCombustible = (combustibleLitros * _precioCombustiblePorLitro).round();

      // Tiempo de ocio
      final tiempoOcio = _jornadaMinutos - tiempoTrabajo - tiempoTrayecto;

      final metrica = MetricaProduccion(
        tecnicoRut: tecnicoRut,
        tecnicoNombre: tecnicoNombre,
        fecha: fecha,
        tiempoTrabajoMin: tiempoTrabajo,
        tiempoTrayectoMin: tiempoTrayecto,
        tiempoOcioMin: tiempoOcio > 0 ? tiempoOcio : 0,
        tiempoPromedioOrdenMin: completadas > 0 ? tiempoTrabajo ~/ completadas : 0,
        kmRecorridos: kmTotal,
        combustibleLitros: combustibleLitros,
        costoCombustible: costoCombustible,
        ordenesAsignadas: ordenes.length,
        ordenesCompletadas: completadas,
        quiebres: quiebres,
        porcentajeProductividad: porcentajeProductividad,
        porcentajeQuiebre: porcentajeQuiebre,
        productividadVsQuiebre: productividadVsQuiebre,
        altasCompletadas: altas,
        bajasCompletadas: bajas,
        reparacionesCompletadas: reparaciones,
        horaPico: horaPico,
        zonaMasEficiente: zonaMasEficiente,
      );

      // Guardar en Supabase
      await _guardarMetrica(metrica);

      return metrica;

    } catch (e) {
      print('❌ [Produccion] Error calculando métricas: $e');
      return null;
    }
  }

  // Método interno para extraer equipos de una lista de órdenes
  Future<void> _extraerEquiposDeOrdenes({
    required String tecnicoRut,
    required String tecnicoNombre,
    required DateTime fecha,
    required List<Map<String, dynamic>> ordenes,
  }) async {
    try {
      for (final orden in ordenes) {
        final tipo = orden['Tipo de Actividad']?.toString() ?? '';
        
        if (!tipo.toLowerCase().contains('baja')) continue;

        final pasos = orden['Pasos']?.toString() ?? '';
        
        final serialesMatch = RegExp(r'Numero de serie\s*:\s*([A-Z0-9]+)', caseSensitive: false)
            .allMatches(pasos);
        
        for (final match in serialesMatch) {
          final serial = match.group(1) ?? '';
          if (serial.isEmpty) continue;

          String tipoEquipo = 'Equipo';
          if (pasos.contains('MTA')) tipoEquipo = 'MTA/Router';
          else if (pasos.contains('D-Box')) tipoEquipo = 'D-Box';
          else if (pasos.contains('Extensor')) tipoEquipo = 'Extensor WiFi';
          else if (pasos.contains('CM')) tipoEquipo = 'Cable Modem';

          final equipo = EquipoReversa(
            tecnicoRut: tecnicoRut,
            tecnicoNombre: tecnicoNombre,
            serial: serial,
            tipoEquipo: tipoEquipo,
            ot: orden['Orden de Trabajo']?.toString() ?? '',
            cliente: orden['Cliente']?.toString(),
            direccion: orden['Dirección']?.toString(),
            fechaDesinstalacion: fecha,
            estado: 'pendiente',
          );

          await _guardarEquipoReversa(equipo);
        }
      }
    } catch (e) {
      print('❌ [Reversa] Error extrayendo equipos: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // CONSULTA RGU DESDE SUPABASE (produccion_traza)
  // ═══════════════════════════════════════════════════════════

  /// Calcular días operativos según turno (igual que la vista SQL)
  Future<int> _calcularDiasOperativos(int mes, int anno, String tipoTurno, {DateTime? hasta}) async {
    try {
      final primerDia = DateTime(anno, mes, 1);
      final ultimoDia = hasta != null
          ? DateTime(hasta.year, hasta.month, hasta.day) // solo hasta esa fecha
          : DateTime(anno, mes + 1, 0);                  // fin del mes completo
      final diasMes = ultimoDia.day;

      // Contar domingos hasta la fecha límite
      int domingos = 0;
      for (int dia = 1; dia <= diasMes; dia++) {
        final fecha = DateTime(anno, mes, dia);
        if (fecha.isBefore(primerDia)) continue;
        if (fecha.weekday == DateTime.sunday) domingos++;
      }

      // Consultar festivos en el rango
      int festivos = 0;
      try {
        final fechaInicio = '$anno-${mes.toString().padLeft(2, '0')}-01';
        final fechaFin = '$anno-${mes.toString().padLeft(2, '0')}-${diasMes.toString().padLeft(2, '0')}';
        
        final response = await _supabase
            .from('festivos_chile')
            .select('fecha')
            .gte('fecha', fechaInicio)
            .lte('fecha', fechaFin);
        
        festivos = (response as List).length;
      } catch (e) {
        print('⚠️ [DiasOperativos] No se pudo obtener festivos: $e');
      }

      // Contar sábados para turno 5x1/5x2
      int sabados = 0;
      for (int dia = 1; dia <= diasMes; dia++) {
        final fecha = DateTime(anno, mes, dia);
        if (fecha.isBefore(primerDia)) continue;
        if (fecha.weekday == DateTime.saturday) sabados++;
      }

      // Calcular según turno
      int diasOperativos;
      if (tipoTurno == '6x1') {
        // 6 días trabajo, 1 descanso (domingo): descuenta solo domingos
        diasOperativos = diasMes - domingos - festivos;
      } else if (tipoTurno == '5x1') {
        // 5 días trabajo, descuenta sábados y domingos (igual que 5x2 clásico)
        diasOperativos = diasMes - sabados - domingos - festivos;
      } else {
        // 5x2 por defecto: descuenta sábados + domingos
        diasOperativos = diasMes - sabados - domingos - festivos;
      }

      if (diasOperativos < 0) diasOperativos = 0;

      print('📅 [DiasOperativos] Mes $mes/$anno ($tipoTurno) hasta día $diasMes: $diasOperativos días operativos');
      
      return diasOperativos;
    } catch (e) {
      print('❌ [DiasOperativos] Error: $e');
      return 22; // Fallback
    }
  }

  /// Normaliza una fecha de fecha_trabajo y retorna las partes [dia, mes, anno]
  /// Soporta: "DD/MM/YY", "DD/MM/YYYY", "DD.MM.YY", "DD.MM.YYYY"
  List<String>? _partirFecha(String fechaStr) {
    final normalizada = fechaStr.replaceAll('.', '/');
    final partes = normalizada.split('/');
    if (partes.length != 3) return null;
    return partes;
  }

  /// Convierte período de formato "YYYY-MM" a "MM-YYYY"
  /// (formato usado por calidad_api_script)
  String _convertirPeriodo(String periodo) {
    final partes = periodo.split('-');
    if (partes.length == 2 && partes[0].length == 4) {
      return '${partes[1]}-${partes[0]}'; // "2026-03" → "03-2026"
    }
    return periodo;
  }

  /// Obtener resumen del mes con datos de RGU desde Supabase
  Future<Map<String, dynamic>> obtenerResumenMesRGU(
    String rutTecnico, {
    int? mes,
    int? anno,
  }) async {
    final now = DateTime.now();
    final mesConsulta = mes ?? now.month;
    final annoConsulta = anno ?? now.year;

    try {
      // Obtener tipo de turno Y tipo de contrato del técnico
      String tipoTurno = '5x2';
      String tipoContrato = 'nuevo';
      try {
        final tecnicoResponse = await _supabase
            .from('tecnicos_traza_zc')
            .select('tipo_turno, tipo_contrato')
            .eq('rut', rutTecnico)
            .maybeSingle();
        
        if (tecnicoResponse != null) {
          tipoContrato = tecnicoResponse['tipo_contrato']?.toString() ?? 'CN';
          // Derivar turno desde el tipo de contrato
          if (tipoContrato.toUpperCase() == 'CN') {
            tipoTurno = '6x1'; // Contrato Nuevo → 6 días trabajo, 1 descanso
          } else if (tipoContrato.toUpperCase() == 'CA') {
            tipoTurno = '5x1'; // Contrato Antiguo → 5 días trabajo, 2 descansos
          } else {
            tipoTurno = tecnicoResponse['tipo_turno']?.toString() ?? '5x2';
          }
        }
      } catch (e) {
        print('⚠️ [Produccion] No se pudo obtener tipo de turno/contrato: $e');
      }

      // Calcular días operativos según turno
      final diasOperativos = await _calcularDiasOperativos(mesConsulta, annoConsulta, tipoTurno);
      
      // Calcular días hábiles del mes (L-S - feriados) - PARA COMPATIBILIDAD
      final diasHabiles = diasOperativos; // Ahora usa días operativos
      final feriadosEnMes = 0; // Ya está incluido en días operativos

      // Obtener marcas de asistencia desde GeoVictoria (Supabase)
      final marcas = await _marcasService.obtenerMarcas(
        rutTecnico: rutTecnico,
        mes: mesConsulta,
        anio: annoConsulta,
      );
      
      print('📊 [Produccion] Marcas GeoVictoria:');
      print('   - Trabajados: ${marcas.diasTrabajados}');
      print('   - Ausentes: ${marcas.diasAusentes}');
      print('   - Feriados: ${marcas.diasFeriados}');
      print('   - Vacaciones: ${marcas.diasVacaciones}');

      // ═══════════════════════════════════════════════════════════════════
      // BÚSQUEDA HÍBRIDA: Por RUT y por NOMBRE (fix para datos legacy)
      // ═══════════════════════════════════════════════════════════════════
      
      // 1️⃣ Buscar por RUT (método principal)
      final responseRut = await _supabase
          .from('produccion')
          .select()
          .eq('rut_tecnico', rutTecnico);

      List<dynamic> ordenesPorRut = responseRut as List? ?? [];
      print('🔍 [Produccion] Órdenes por RUT ($rutTecnico): ${ordenesPorRut.length}');

      // 2️⃣ Obtener el nombre del técnico desde tecnicos_traza_zc
      String? nombreTecnico;
      try {
        final tecnicoResponse = await _supabase
            .from('tecnicos_traza_zc')
            .select('nombre_completo')
            .eq('rut', rutTecnico)
            .maybeSingle();
        
        if (tecnicoResponse != null) {
          nombreTecnico = tecnicoResponse['nombre_completo']?.toString();
          print('👤 [Produccion] Nombre del técnico: $nombreTecnico');
        }
      } catch (e) {
        print('⚠️ [Produccion] Error obteniendo nombre del técnico: $e');
      }

      // 3️⃣ Buscar también por NOMBRE (para datos legacy con RUT incorrecto)
      List<dynamic> ordenesPorNombre = [];
      if (nombreTecnico != null && nombreTecnico.isNotEmpty) {
        final responseNombre = await _supabase
            .from('produccion')
            .select()
            .eq('tecnico', nombreTecnico);
        
        ordenesPorNombre = responseNombre as List? ?? [];
        print('🔍 [Produccion] Órdenes por NOMBRE ($nombreTecnico): ${ordenesPorNombre.length}');
      }

      // 4️⃣ Combinar y deduplicar — priorizar estado 'Completado' sobre duplicados
      // Si el mismo orden_trabajo aparece como Cancelado Y Completado, queda Completado
      final Map<String, dynamic> ordenesMap = {};

      for (var orden in [...ordenesPorRut, ...ordenesPorNombre]) {
        final ordenId = orden['orden_trabajo']?.toString() ?? '';
        if (ordenId.isEmpty) continue;
        final fechaTrabajo = orden['fecha_trabajo']?.toString() ?? '';
        final key = '$ordenId-$fechaTrabajo';

        if (!ordenesMap.containsKey(key)) {
          ordenesMap[key] = orden;
        } else {
          // Si la nueva versión es Completado y la actual no lo es, reemplazar
          final esCompletado = orden['estado']?.toString() == 'Completado';
          final actualCompletado = ordenesMap[key]['estado']?.toString() == 'Completado';
          if (esCompletado && !actualCompletado) {
            ordenesMap[key] = orden;
          }
        }
      }

      final List<dynamic> todasOrdenes = ordenesMap.values.toList();
      print('📊 [Produccion] Total órdenes únicas combinadas: ${todasOrdenes.length}');

      // Filtrar por mes y año seleccionado
      // Soporta: "DD/MM/YY", "DD/MM/YYYY", "DD.MM.YY", "DD.MM.YYYY"
      final ordenesMes = todasOrdenes.where((orden) {
        final fechaStr = orden['fecha_trabajo']?.toString() ?? '';
        final partes = _partirFecha(fechaStr);
        if (partes == null) return false;

        final mesOrden = int.tryParse(partes[1]) ?? 0;
        var annoOrden = int.tryParse(partes[2]) ?? 0;
        if (annoOrden < 100) annoOrden = 2000 + annoOrden;

        return mesOrden == mesConsulta && annoOrden == annoConsulta;
      }).toList();

      if (ordenesMes.isEmpty) {
        final hayDatosGeo = marcas.diasTrabajados > 0 || marcas.diasAusentes > 0 || 
                             marcas.diasFeriados > 0 || marcas.diasVacaciones > 0;
        
        return {
          'totalRGU': 0.0,
          'promedioRGU': 0.0,
          'tipoContrato': tipoContrato,
          // Desglose por tecnología (contrato antiguo)
          'rguRedNeutra': 0.0,
          'ptosHfc': 0.0,
          'rguFtth': 0.0,
          'ordenesCompletadas': 0,
          'ordenesAsignadas': 0,
          'ordenesCanceladas': 0,
          'ordenesNoRealizadas': 0,
          'diasTrabajados': hayDatosGeo ? marcas.diasTrabajados : 0,
          'diasOperativos': diasOperativos,
          'tipoTurno': tipoTurno,
          'diasPX0': 0,
          'diasPX0List': <Map<String, dynamic>>[],
          'diasAusentes': hayDatosGeo ? marcas.diasAusentes : diasHabiles,
          'diasHabiles': diasHabiles,
          'feriados': hayDatosGeo ? marcas.diasFeriados : feriadosEnMes,
          'vacaciones': hayDatosGeo ? marcas.diasVacaciones : 0,
          'efectividad': 0.0,
          'porcentajeQuiebre': 0.0,
        };
      }

      // Agrupar órdenes por fecha para análisis detallado
      Map<String, List<dynamic>> ordenesPorFecha = {};
      for (var orden in ordenesMes) {
        final fecha = orden['fecha_trabajo']?.toString() ?? '';
        if (fecha.isNotEmpty) {
          ordenesPorFecha.putIfAbsent(fecha, () => []);
          ordenesPorFecha[fecha]!.add(orden);
        }
      }

      // Analizar cada día
      int completadas = 0;
      int canceladas = 0;
      int noRealizadas = 0;
      double totalRGU = 0;
      // Desglose por tecnología (contrato antiguo)
      double rguRedNeutra = 0;
      double ptosHfc = 0;
      double rguFtth = 0;
      Set<String> diasConProduccion = {};
      List<Map<String, dynamic>> diasPX0List = [];

      for (var entry in ordenesPorFecha.entries) {
        final fecha = entry.key;
        final ordenesDelDia = entry.value;

        int completadasDia = 0;
        double rguDia = 0;

        for (var orden in ordenesDelDia) {
          final estado = orden['estado']?.toString() ?? '';

          if (estado == 'Completado') {
            completadas++;
            completadasDia++;
            final rgu = (orden['rgu_total'] as num?)?.toDouble() ?? 0;
            totalRGU += rgu;
            rguDia += rgu;

            // Acumular por tecnología
            final tecno = orden['tecnologia']?.toString() ?? 'RED_NEUTRA';
            if (tecno == 'HFC') {
              ptosHfc += (orden['puntos_hfc'] as num?)?.toDouble() ?? 0;
            } else if (tecno == 'FTTH') {
              rguFtth += rgu;
            } else {
              rguRedNeutra += rgu;
            }
          } else if (estado == 'Cancelado') {
            canceladas++;
          } else if (estado == 'No Realizada') {
            noRealizadas++;
          }
        }

        if (completadasDia > 0) {
          diasConProduccion.add(fecha);
        } else {
          diasPX0List.add({
            'fecha': fecha,
            'ordenes': ordenesDelDia.length,
          });
        }
      }

      final totalAsignadas = completadas + canceladas + noRealizadas;
      final diasPX0 = diasPX0List.length;
      
      // ESTRATEGIA HÍBRIDA: Combinar GeoVictoria (vacaciones/feriados) con Producción (días trabajados)
      int diasTrabajados;
      int diasAusentesFinales;
      int feriadosFinales;
      int vacacionesFinales;
      
      // Calcular días trabajados desde producción (días con órdenes + PX-0)
      final diasTrabajadosProduccion = diasConProduccion.length + diasPX0;
      
      // Total de días registrados en GeoVictoria
      final totalDiasGeoVictoria = marcas.diasTrabajados + marcas.diasAusentes + 
                                    marcas.diasFeriados + marcas.diasVacaciones;

      // Para el mes en curso, calcular solo días operativos YA TRANSCURRIDOS
      // (evita mostrar días futuros como ausentes)
      final hoy = DateTime.now();
      final esElMesActual = mesConsulta == hoy.month && annoConsulta == hoy.year;
      final int diasHabilesTranscurridos;
      if (esElMesActual) {
        diasHabilesTranscurridos = await _calcularDiasOperativos(
          mesConsulta, annoConsulta, tipoTurno, hasta: hoy,
        );
        print('📅 [Produccion] Mes en curso: $diasHabilesTranscurridos días operativos transcurridos hasta hoy (de $diasHabiles totales)');
      } else {
        diasHabilesTranscurridos = diasHabiles;
      }
      
      // Si GeoVictoria tiene datos del mes completo (o casi), confiar en sus días trabajados
      final geoVictoriaTieneMesCompleto = totalDiasGeoVictoria >= (diasHabilesTranscurridos * 0.8);
      
      if (geoVictoriaTieneMesCompleto && marcas.diasTrabajados > 0) {
        diasTrabajados = marcas.diasTrabajados;
        diasAusentesFinales = marcas.diasAusentes;
        feriadosFinales = marcas.diasFeriados;
        vacacionesFinales = marcas.diasVacaciones;
        print('✅ [Produccion] Usando datos completos de GeoVictoria (${totalDiasGeoVictoria} días registrados)');
      } else {
        // GeoVictoria tiene datos parciales - HÍBRIDO
        diasTrabajados = diasTrabajadosProduccion;
        feriadosFinales = marcas.diasFeriados > 0 ? marcas.diasFeriados : feriadosEnMes;
        vacacionesFinales = marcas.diasVacaciones;
        
        // Ausentes = días transcurridos - trabajados - feriados - vacaciones
        // Se usan diasHabilesTranscurridos para NO incluir días futuros
        diasAusentesFinales = (diasHabilesTranscurridos - diasTrabajados - feriadosFinales - vacacionesFinales)
            .clamp(0, diasHabilesTranscurridos);
        
        print('🔀 [Produccion] Usando datos HÍBRIDOS:');
        print('   - Días trabajados: $diasTrabajados (de producción: ${diasConProduccion.length} + PX-0: $diasPX0)');
        print('   - Días hábiles transcurridos: $diasHabilesTranscurridos');
        print('   - Vacaciones: $vacacionesFinales (de GeoVictoria)');
        print('   - Feriados: $feriadosFinales (de GeoVictoria)');
      }

      // Promedio RGU/día = total RGU / días trabajados (GeoVictoria o producción)
      final diasConProd = diasConProduccion.length;
      final divisor = diasTrabajados > 0 ? diasTrabajados : (diasConProd > 0 ? diasConProd : 1);
      final promedioRGU = totalRGU / divisor;
      
      print('📊 [Produccion] CÁLCULO PROMEDIO:');
      print('   - Total RGU: $totalRGU');
      print('   - Días trabajados (divisor): $diasTrabajados');
      print('   - Días con producción en Supabase: $diasConProd');
      print('   - Días operativos del mes: $diasOperativos ($tipoTurno)');
      print('   - Promedio RGU/día: ${promedioRGU.toStringAsFixed(2)}');

      final efectividad = totalAsignadas > 0
          ? (completadas / totalAsignadas) * 100
          : 0.0;

      final porcentajeQuiebre = totalAsignadas > 0
          ? ((canceladas + noRealizadas) / totalAsignadas) * 100
          : 0.0;

      print('📊 [Produccion] ═══════════════════════════════════════════');
      print('📊 [Produccion] RESUMEN FINAL MES: $mesConsulta/$annoConsulta');
      print('📊 [Produccion] ═══════════════════════════════════════════');
      print('   - Turno del técnico: $tipoTurno');
      print('   - Días operativos del mes: $diasOperativos');
      print('   - Días trabajados (reales): $diasTrabajados');
      print('   - Días con producción: ${diasConProduccion.length}');
      print('   - Días PX-0: $diasPX0');
      print('   - Días ausentes: $diasAusentesFinales');
      print('   - Vacaciones: $vacacionesFinales');
      print('   - Feriados: $feriadosFinales');
      print('   ─────────────────────────────────────────────────────────');
      print('   - Total RGU: ${totalRGU.toStringAsFixed(1)}');
      print('   - Divisor (días operativos): $diasOperativos');
      print('   - ⭐ PROMEDIO RGU/DÍA: ${promedioRGU.toStringAsFixed(2)}');
      print('📊 [Produccion] ═══════════════════════════════════════════');

      return {
        'totalRGU': totalRGU,
        'promedioRGU': promedioRGU,
        'tipoContrato': tipoContrato,
        // Desglose por tecnología (se usa cuando tipo_contrato == 'antiguo')
        'rguRedNeutra': rguRedNeutra,
        'ptosHfc': ptosHfc,
        'rguFtth': rguFtth,
        'ordenesCompletadas': completadas,
        'ordenesAsignadas': totalAsignadas,
        'ordenesCanceladas': canceladas,
        'ordenesNoRealizadas': noRealizadas,
        'diasConProduccion': diasConProduccion.length,
        'diasTrabajados': diasTrabajados,
        'diasOperativos': diasOperativos,
        'tipoTurno': tipoTurno,
        'diasPX0': diasPX0,
        'diasPX0List': diasPX0List,
        'diasAusentes': diasAusentesFinales,
        'diasHabiles': diasHabiles,
        'feriados': feriadosFinales,
        'vacaciones': vacacionesFinales,
        'efectividad': efectividad,
        'porcentajeQuiebre': porcentajeQuiebre,
      };
    } catch (e) {
      print('❌ [Produccion] Error obteniendo resumen RGU: $e');
      return {
        'totalRGU': 0.0,
        'promedioRGU': 0.0,
        'tipoContrato': 'nuevo',
        'rguRedNeutra': 0.0,
        'ptosHfc': 0.0,
        'rguFtth': 0.0,
        'ordenesCompletadas': 0,
        'ordenesAsignadas': 0,
        'ordenesCanceladas': 0,
        'ordenesNoRealizadas': 0,
        'diasTrabajados': 0,
        'diasOperativos': 22,
        'tipoTurno': '5x2',
        'diasPX0': 0,
        'diasPX0List': <Map<String, dynamic>>[],
        'diasAusentes': 0,
        'diasHabiles': 0,
        'feriados': 0,
        'vacaciones': 0,
        'efectividad': 0.0,
        'porcentajeQuiebre': 0.0,
      };
    }
  }

  /// Obtener detalle por día con RGU
  Future<List<Map<String, dynamic>>> obtenerDetallePorDiaRGU(
    String rutTecnico, {
    int? mes,
    int? anno,
  }) async {
    final now = DateTime.now();
    final mesConsulta = mes ?? now.month;
    final annoConsulta = anno ?? now.year;

    try {
      // ═══════════════════════════════════════════════════════════════════
      // BÚSQUEDA HÍBRIDA: Por RUT y por NOMBRE (fix para datos legacy)
      // ═══════════════════════════════════════════════════════════════════
      
      // 1️⃣ Buscar por RUT
      final responseRut = await _supabase
          .from('produccion')
          .select()
          .eq('rut_tecnico', rutTecnico)
          .eq('estado', 'Completado');

      List<dynamic> ordenesPorRut = responseRut as List? ?? [];

      // 2️⃣ Obtener nombre del técnico
      String? nombreTecnico;
      try {
        final tecnicoResponse = await _supabase
            .from('tecnicos_traza_zc')
            .select('nombre_completo')
            .eq('rut', rutTecnico)
            .maybeSingle();
        
        if (tecnicoResponse != null) {
          nombreTecnico = tecnicoResponse['nombre_completo']?.toString();
        }
      } catch (e) {
        print('⚠️ [Detalle] Error obteniendo nombre del técnico: $e');
      }

      // 3️⃣ Buscar también por NOMBRE
      List<dynamic> ordenesPorNombre = [];
      if (nombreTecnico != null && nombreTecnico.isNotEmpty) {
        final responseNombre = await _supabase
            .from('produccion')
            .select()
            .eq('tecnico', nombreTecnico)
            .eq('estado', 'Completado');
        
        ordenesPorNombre = responseNombre as List? ?? [];
      }

      // 4️⃣ Combinar y deduplicar
      final Set<String> ordenesVistas = {};
      final List<dynamic> todasOrdenes = [];

      for (var orden in [...ordenesPorRut, ...ordenesPorNombre]) {
        final ordenId = orden['orden_trabajo']?.toString() ?? '';
        final fechaTrabajo = orden['fecha_trabajo']?.toString() ?? '';
        final key = '$ordenId-$fechaTrabajo';
        
        if (ordenId.isNotEmpty && !ordenesVistas.contains(key)) {
          ordenesVistas.add(key);
          todasOrdenes.add(orden);
        }
      }

      // Filtrar por mes y año — soporta DD/MM/YY y DD.MM.YY
      final ordenesMes = todasOrdenes.where((orden) {
        final fechaStr = orden['fecha_trabajo']?.toString() ?? '';
        final partes = _partirFecha(fechaStr);
        if (partes == null) return false;

        final mesOrden = int.tryParse(partes[1]) ?? 0;
        var annoOrden = int.tryParse(partes[2]) ?? 0;
        if (annoOrden < 100) annoOrden = 2000 + annoOrden;

        return mesOrden == mesConsulta && annoOrden == annoConsulta;
      }).toList();

      // Filtro adicional en Dart para asegurar solo completadas
      final ordenesCompletadas = ordenesMes.where((orden) {
        return orden['estado']?.toString() == 'Completado';
      }).toList();

      // Agrupar por día (usar solo órdenes completadas)
      Map<String, Map<String, dynamic>> porDia = {};

      for (var orden in ordenesCompletadas) {
        final fecha = orden['fecha_trabajo']?.toString() ?? '';
        if (fecha.isEmpty) continue;

        if (!porDia.containsKey(fecha)) {
          porDia[fecha] = {
            'fecha': fecha,
            'ordenesCompletadas': 0,
            'rguTotal': 0.0,
            // Desglose por tecnología
            'rguRedNeutra': 0.0,
            'ptosHfc': 0.0,
            'rguFtth': 0.0,
            'tecnologias': <String>{},  // Set de tecnologías del día
            'ordenes': <Map<String, dynamic>>[],
          };
        }

        final rgu = (orden['rgu_total'] as num?)?.toDouble() ?? 0;
        final tecno = orden['tecnologia']?.toString() ?? 'RED_NEUTRA';
        final ptsHfc = (orden['puntos_hfc'] as num?)?.toDouble() ?? 0;

        porDia[fecha]!['ordenesCompletadas'] = (porDia[fecha]!['ordenesCompletadas'] as int) + 1;
        porDia[fecha]!['rguTotal'] = (porDia[fecha]!['rguTotal'] as double) + rgu;

        // Acumular por tecnología
        (porDia[fecha]!['tecnologias'] as Set<String>).add(tecno);
        if (tecno == 'HFC') {
          porDia[fecha]!['ptosHfc'] = (porDia[fecha]!['ptosHfc'] as double) + ptsHfc;
        } else if (tecno == 'FTTH') {
          porDia[fecha]!['rguFtth'] = (porDia[fecha]!['rguFtth'] as double) + rgu;
        } else {
          porDia[fecha]!['rguRedNeutra'] = (porDia[fecha]!['rguRedNeutra'] as double) + rgu;
        }

        // Agregar detalle de la orden
        (porDia[fecha]!['ordenes'] as List<Map<String, dynamic>>).add({
          'orden_trabajo': orden['orden_trabajo'],
          'tipo_orden': orden['tipo_orden'],
          'tecnologia': tecno,
          'rgu_base': (orden['rgu_base'] as num?)?.toDouble() ?? 0,
          'rgu_adicional': (orden['rgu_adicional'] as num?)?.toDouble() ?? 0,
          'rgu_total': rgu,
          'puntos_hfc': ptsHfc,
          'categoria_hfc': orden['categoria_hfc']?.toString() ?? '',
          'cant_dbox': orden['cant_dbox'] ?? 0,
          'cant_extensores': orden['cant_extensores'] ?? 0,
        });
      }

      // Convertir Set<String> tecnologias a List<String> para serialización
      for (var dia in porDia.values) {
        dia['tecnologias'] = (dia['tecnologias'] as Set<String>).toList();
      }

      // Convertir a lista y ordenar por fecha (más reciente primero)
      final lista = porDia.values.toList();
      lista.sort((a, b) {
        // Parsear fechas D/MM/YYYY o D.MM.YY
        final partesA = _partirFecha(a['fecha'] as String);
        final partesB = _partirFecha(b['fecha'] as String);

        if (partesA != null && partesB != null) {
          var annoA = int.parse(partesA[2]);
          var annoB = int.parse(partesB[2]);
          if (annoA < 100) annoA = 2000 + annoA;
          if (annoB < 100) annoB = 2000 + annoB;
          final fechaA = DateTime(annoA, int.parse(partesA[1]), int.parse(partesA[0]));
          final fechaB = DateTime(annoB, int.parse(partesB[1]), int.parse(partesB[0]));
          return fechaB.compareTo(fechaA); // Más reciente primero
        }
        return 0;
      });

      return lista;
    } catch (e) {
      print('❌ [Produccion] Error obteniendo detalle por día RGU: $e');
      return [];
    }
  }

  // Obtener resumen del mes (método antiguo - mantener para compatibilidad)
  Future<Map<String, dynamic>> obtenerResumenMes(String tecnicoRut, {DateTime? mes}) async {
    final fecha = mes ?? DateTime.now();
    final inicioMes = DateTime(fecha.year, fecha.month, 1);
    final finMes = DateTime(fecha.year, fecha.month + 1, 0);
    
    try {
      final response = await _supabase
          .from('metricas_produccion')
          .select()
          .eq('tecnico_rut', tecnicoRut)
          .gte('fecha', inicioMes.toIso8601String().split('T')[0])
          .lte('fecha', finMes.toIso8601String().split('T')[0]);

      final metricas = (response as List).map((json) => MetricaProduccion.fromJson(json)).toList();

      if (metricas.isEmpty) {
        return {
          'diasTrabajados': 0,
          'ordenesTotales': 0,
          'ordenesCompletadas': 0,
          'quiebresTotales': 0,
          'kmTotales': 0.0,
          'tiempoTrabajoTotal': 0,
          'tiempoTrayectoTotal': 0,
          'combustibleTotal': 0.0,
          'costoTotal': 0,
          'promedioOrdenesDia': 0.0,
          'porcentajeProductividad': 0.0,
          'porcentajeQuiebre': 0.0,
        };
      }

      int ordenesTotales = 0;
      int ordenesCompletadas = 0;
      int quiebresTotales = 0;
      double kmTotales = 0;
      int tiempoTrabajoTotal = 0;
      int tiempoTrayectoTotal = 0;
      double combustibleTotal = 0;
      int costoTotal = 0;

      for (final m in metricas) {
        ordenesTotales += m.ordenesAsignadas;
        ordenesCompletadas += m.ordenesCompletadas;
        quiebresTotales += m.quiebres;
        kmTotales += m.kmRecorridos;
        tiempoTrabajoTotal += m.tiempoTrabajoMin;
        tiempoTrayectoTotal += m.tiempoTrayectoMin;
        combustibleTotal += m.combustibleLitros;
        costoTotal += m.costoCombustible;
      }

      return {
        'diasTrabajados': metricas.length,
        'ordenesTotales': ordenesTotales,
        'ordenesCompletadas': ordenesCompletadas,
        'quiebresTotales': quiebresTotales,
        'kmTotales': kmTotales,
        'tiempoTrabajoTotal': tiempoTrabajoTotal,
        'tiempoTrayectoTotal': tiempoTrayectoTotal,
        'combustibleTotal': combustibleTotal,
        'costoTotal': costoTotal,
        'promedioOrdenesDia': metricas.isNotEmpty ? ordenesCompletadas / metricas.length : 0.0,
        'porcentajeProductividad': ordenesTotales > 0 ? (ordenesCompletadas / ordenesTotales) * 100 : 0.0,
        'porcentajeQuiebre': ordenesTotales > 0 ? (quiebresTotales / ordenesTotales) * 100 : 0.0,
        'metricas': metricas,
      };
    } catch (e) {
      print('❌ [Produccion] Error obteniendo resumen: $e');
      return {};
    }
  }

  // ═══════════════════════════════════════════════════════════
  // RANKING DE PRODUCCIÓN (usa v_ranking_produccion de SQL)
  // ═══════════════════════════════════════════════════════════

  /// Obtener ranking de técnicos por RGU/día calculando directo desde produccion
  Future<Map<String, dynamic>> obtenerRankingMes({
    int? mes,
    int? anno,
  }) async {
    final now = DateTime.now();
    final mesConsulta = mes ?? now.month;
    final annoConsulta = anno ?? now.year;

    final mesStr = mesConsulta.toString().padLeft(2, '0');
    final annoStr = (annoConsulta % 100).toString().padLeft(2, '0');

    print('🔍 [Ranking] Calculando desde produccion — mes: $mesConsulta/$annoConsulta');

    try {
      // Filtrar por mes/año usando el patrón de fecha almacenada ("DD/MM/YY" o "DD.MM.YY")
      final response = await _supabase
          .from('produccion')
          .select('rut_tecnico, tecnico, rgu_total, fecha_trabajo')
          .or('fecha_trabajo.like.%/$mesStr/$annoStr,fecha_trabajo.like.%.$mesStr.$annoStr')
          .eq('estado', 'Completado')
          .limit(10000); // Evitar truncación del default de Supabase (1000)

      final ordenes = List<Map<String, dynamic>>.from(response as List);
      print('🔍 [Ranking] Órdenes del mes encontradas: ${ordenes.length}');

      if (ordenes.isEmpty) {
        return {'ranking': <Map<String, dynamic>>[], 'totalTecnicos': 0};
      }

      // Agrupar por técnico
      final Map<String, Map<String, dynamic>> porTecnico = {};
      for (var o in ordenes) {
        final rut = o['rut_tecnico']?.toString() ?? '';
        if (rut.isEmpty) continue;
        final nombre = o['tecnico']?.toString() ?? rut;
        final rgu = (o['rgu_total'] as num?)?.toDouble() ?? 0.0;
        final fecha = o['fecha_trabajo']?.toString() ?? '';

        if (!porTecnico.containsKey(rut)) {
          porTecnico[rut] = {
            'rut': rut,
            'nombre': nombre,
            'rguTotal': 0.0,
            'ordenes': 0,
            'dias': <String>{},         // todos los días con órdenes
            'diasConRgu': <String>{},   // solo días con RGU > 0
            'rguPorDia': <String, double>{}, // acumulado de RGU por fecha
          };
        }
        porTecnico[rut]!['rguTotal'] =
            (porTecnico[rut]!['rguTotal'] as double) + rgu;
        porTecnico[rut]!['ordenes'] =
            (porTecnico[rut]!['ordenes'] as int) + 1;
        (porTecnico[rut]!['dias'] as Set<String>).add(fecha);

        // Acumular RGU por fecha para detectar días productivos
        final rguPorDia = porTecnico[rut]!['rguPorDia'] as Map<String, double>;
        rguPorDia[fecha] = (rguPorDia[fecha] ?? 0.0) + rgu;
      }

      // Calcular promedio usando solo días con RGU real (excluye días PX-0)
      final list = porTecnico.values.map((t) {
        final rguPorDia = t['rguPorDia'] as Map<String, double>;
        // Días productivos = fechas donde el total de RGU acumulado es > 0
        final diasConRguReal = rguPorDia.values.where((v) => v > 0).length;
        final diasTotal = (t['dias'] as Set<String>).length;
        // Usar días productivos; si todos son PX-0, usar días totales para no dividir por 0
        final divisor = diasConRguReal > 0 ? diasConRguReal : (diasTotal > 0 ? diasTotal : 1);
        return <String, dynamic>{
          'rut': t['rut'],
          'nombre': t['nombre'],
          'rguTotal': t['rguTotal'],
          'ordenes': t['ordenes'],
          'diasTrabajados': diasConRguReal,
          'promedioRGU': (t['rguTotal'] as double) / divisor,
          'tipoTurno': '5x2',
        };
      }).toList();

      list.sort((a, b) =>
          (b['promedioRGU'] as double).compareTo(a['promedioRGU'] as double));

      // Asignar posiciones
      for (var i = 0; i < list.length; i++) {
        list[i]['posicion'] = i + 1;
      }

      print('🏆 [Ranking] ${list.length} técnicos — Top 3:');
      for (var i = 0; i < list.length && i < 3; i++) {
        final t = list[i];
        print('   #${t['posicion']} ${t['nombre']} — ${(t['promedioRGU'] as double).toStringAsFixed(2)} RGU/día');
      }

      return {'ranking': list, 'totalTecnicos': list.length};
    } catch (e, stack) {
      print('❌ [Ranking] Error: $e');
      print('❌ [Ranking] Stack: $stack');
      return {'ranking': <Map<String, dynamic>>[], 'totalTecnicos': 0};
    }
  }

  /// Obtener posición específica de un técnico en el ranking
  Future<Map<String, dynamic>> obtenerPosicionTecnico(
    String rutTecnico, {
    int? mes,
    int? anno,
  }) async {
    print('🎯 [Posicion] Buscando RUT: $rutTecnico');

    final rankingData = await obtenerRankingMes(mes: mes, anno: anno);
    final ranking = List<Map<String, dynamic>>.from(rankingData['ranking'] as List);

    print('🎯 [Posicion] Ranking tiene ${ranking.length} técnicos');

    // Buscar al técnico
    Map<String, dynamic>? tecnicoEncontrado;
    for (var t in ranking) {
      if (t['rut'] == rutTecnico) {
        tecnicoEncontrado = t;
        break;
      }
    }

    print('🎯 [Posicion] Técnico encontrado: $tecnicoEncontrado');

    // Devolver TODOS los técnicos, no solo top 10
    // Nombre del campo sigue siendo 'top10' para no romper compatibilidad
    final todosLosTecnicos = ranking.toList();

    if (tecnicoEncontrado == null) {
      return {
        'posicion': 0,
        'totalTecnicos': ranking.length,
        'rguTotal': 0.0,
        'promedioRGU': 0.0,
        'ordenes': 0,
        'diasTrabajados': 0,
        'tipoTurno': '5x2',
        'top10': todosLosTecnicos, // Todos los técnicos, no solo top 10
      };
    }

    return {
      'posicion': tecnicoEncontrado['posicion'],
      'totalTecnicos': ranking.length,
      'rguTotal': tecnicoEncontrado['rguTotal'],
      'promedioRGU': tecnicoEncontrado['promedioRGU'] ?? 0.0,
      'ordenes': tecnicoEncontrado['ordenes'],
      'diasTrabajados': tecnicoEncontrado['diasTrabajados'] ?? 0,
      'tipoTurno': tecnicoEncontrado['tipoTurno'] ?? '5x2',
      'nombre': tecnicoEncontrado['nombre'],
      'top10': todosLosTecnicos, // Todos los técnicos, no solo top 10
    };
  }

  // ═══════════════════════════════════════════════════════════
  // MÉTRICAS DE TIEMPO
  // ═══════════════════════════════════════════════════════════

  /// Obtener métricas de tiempo del técnico en el mes
  Future<Map<String, dynamic>> obtenerMetricasTiempo(
    String rutTecnico, {
    int? mes,
    int? anno,
  }) async {
    final now = DateTime.now();
    final mesConsulta = mes ?? now.month;
    final annoConsulta = anno ?? now.year;

    try {
      // Incluir órdenes Completadas, Suspendidas, Canceladas y No realizadas para el cálculo de inicio tardío
      final response = await _supabase
          .from('produccion')
          .select('fecha_trabajo, hora_inicio, hora_fin, duracion_min, estado')
          .eq('rut_tecnico', rutTecnico)
          .inFilter('estado', ['Completado', 'Suspendido', 'Cancelado', 'No realizado']);

      final todasOrdenes = List<Map<String, dynamic>>.from(response as List);

      // Filtrar por mes y año — soporta DD/MM/YY y DD.MM.YY
      final ordenesMes = todasOrdenes.where((orden) {
        final fechaStr = orden['fecha_trabajo']?.toString() ?? '';
        final partes = _partirFecha(fechaStr);
        if (partes == null) return false;

        final mesOrden = int.tryParse(partes[1]) ?? 0;
        var annoOrden = int.tryParse(partes[2]) ?? 0;
        if (annoOrden < 100) annoOrden = 2000 + annoOrden;

        return mesOrden == mesConsulta && annoOrden == annoConsulta;
      }).toList();

      if (ordenesMes.isEmpty) {
        return _metricasTiempoVacias();
      }

      // Agrupar por día
      Map<String, List<Map<String, dynamic>>> porDia = {};
      for (var orden in ordenesMes) {
        final fecha = orden['fecha_trabajo']?.toString() ?? '';
        porDia.putIfAbsent(fecha, () => []).add(orden);
      }

      int tiempoTrabajoTotal = 0;
      int tiempoTrayectoTotal = 0;
      int tiempoInicioTardioTotal = 0;
      int tiempoFinTempranoTotal = 0;
      int tiempoProductivoEsperado = 0;
      int diasTrabajados = porDia.length;
      int diasSemana = 0;
      int diasSabado = 0;
      List<Map<String, dynamic>> detalleInicioTardio = [];
      List<Map<String, dynamic>> detalleHorasExtras = [];
      int horasExtrasTotal = 0;
      // Para fallback de hora fin: guardar última hora_fin por fecha
      final Map<String, String> ultimaHoraFinPorDia = {};

      for (var entry in porDia.entries) {
        final fechaStr = entry.key;
        var ordenesDelDia = entry.value;

        // Parsear fecha para determinar día de la semana (DD/MM/YY o DD.MM.YY)
        final partesFecha = _partirFecha(fechaStr);
        DateTime? fecha;
        if (partesFecha != null) {
          final dia  = int.tryParse(partesFecha[0]) ?? 1;
          final mes  = int.tryParse(partesFecha[1]) ?? 1;
          var anno   = int.tryParse(partesFecha[2]) ?? 2025;
          if (anno < 100) anno = 2000 + anno;
          fecha = DateTime(anno, mes, dia);
        }

        // Determinar parámetros según día de la semana
        final esSabado = fecha?.weekday == DateTime.saturday;
        final horaInicioJornada = esSabado ? 600 : 585;   // 10:00 o 9:45
        final horaFinJornada = esSabado ? 900 : 1125;     // 15:00 o 18:45
        final tiempoProductivoDia = esSabado ? 240 : 480; // 4h o 8h

        if (esSabado) {
          diasSabado++;
        } else {
          diasSemana++;
        }

        tiempoProductivoEsperado += tiempoProductivoDia;

        // Ordenar por hora de inicio
        ordenesDelDia.sort((a, b) {
          final horaA = _parseHoraAMinutos(a['hora_inicio']?.toString() ?? '00:00');
          final horaB = _parseHoraAMinutos(b['hora_inicio']?.toString() ?? '00:00');
          return horaA.compareTo(horaB);
        });

        // Sumar tiempo de trabajo del día
        int trabajoDia = 0;
        for (var orden in ordenesDelDia) {
          final duracion = (orden['duracion_min'] as num?)?.toInt() ?? 0;
          trabajoDia += duracion;
        }
        tiempoTrabajoTotal += trabajoDia;

        // Primera y última orden del día
        final primeraHora = _parseHoraAMinutos(ordenesDelDia.first['hora_inicio']?.toString() ?? '00:00');
        final ultimaHora = _parseHoraAMinutos(ordenesDelDia.last['hora_fin']?.toString() ?? '00:00');
        // Registrar hora fin de la última orden del día (string original si existe)
        final ultimaHoraStr = ordenesDelDia.last['hora_fin']?.toString() ?? '';
        ultimaHoraFinPorDia[fechaStr] = ultimaHoraStr;

        // Inicio tardío (si empieza después de la hora esperada pero antes de las 11:00)
        // No contar como atraso si pasa las 11:00 (660 minutos)
        if (primeraHora > horaInicioJornada && primeraHora < 660) {
          final retraso = primeraHora - horaInicioJornada;
          tiempoInicioTardioTotal += retraso;
          // Guardar detalle por día
          detalleInicioTardio.add({
            'fecha': fechaStr,
            'horaInicio': ordenesDelDia.first['hora_inicio']?.toString() ?? '00:00',
            'retraso': retraso,
            'esSabado': esSabado,
          });
        }

        // Fin temprano (si termina antes de la hora esperada)
        if (ultimaHora < horaFinJornada) {
          tiempoFinTempranoTotal += (horaFinJornada - ultimaHora);
        }

        // Tiempo en terreno del día
        final tiempoEnTerreno = ultimaHora - primeraHora;

        // Trayecto/Espera = Tiempo en terreno - Trabajo efectivo
        if (tiempoEnTerreno > trabajoDia) {
          tiempoTrayectoTotal += (tiempoEnTerreno - trabajoDia);
        }
      }

      // Horas extras (vista v_tiempos_tecnicos): minutos posteriores a 18:30 L-V o 15:00 Sáb
      // Horario: 9:45 a 18:30 (L-V) o 10:00 a 15:00 (Sáb)
      try {
        // Usamos select('*') para no fallar si cambian los nombres de columnas
        final extrasResponse = await _supabase
            .from('v_tiempos_tecnicos')
            .select('*')
            .eq('rut_tecnico', rutTecnico)
            .gt('horas_extras_min', 0)
            .order('fecha_trabajo', ascending: false);

        final extras = List<Map<String, dynamic>>.from(extrasResponse as List);

        // Candidatos de nombres de campos para hora fin
        const horaFinKeys = [
          'hora_fin',
          'hora_termino',
          'hora_fin_orden',
          'hora_fin_real',
        ];

        // Agrupar por semana
        Map<String, List<Map<String, dynamic>>> porSemana = {};

        for (final item in extras) {
          final fechaStr = item['fecha_trabajo']?.toString() ?? '';
          final partes = _partirFecha(fechaStr);
          if (partes == null) continue;

          final diaRegistro = int.tryParse(partes[0]) ?? 0;
          final mesRegistro = int.tryParse(partes[1]) ?? 0;
          var annoRegistro = int.tryParse(partes[2]) ?? 0;
          
          // Convertir año de 2 dígitos a 4 dígitos (26 → 2026)
          if (annoRegistro < 100) {
            annoRegistro = 2000 + annoRegistro;
          }
          
          if (mesRegistro != mesConsulta || annoRegistro != annoConsulta) continue;

          final minutos = (item['horas_extras_min'] as num?)?.toInt() ?? 0;
          horasExtrasTotal += minutos;

          // Tomar horaFin de la vista; si no viene, usar fallback de la última orden completada del día
          String horaFin = _pickFirstNonEmpty(item, horaFinKeys);
          if (horaFin.isEmpty) {
            horaFin = ultimaHoraFinPorDia[fechaStr] ?? '';
          }

          // Determinar semana: del 1-7, 8-14, 15-21, 22-28, 29-31
          int semanaNum = 1;
          if (diaRegistro <= 7) {
            semanaNum = 1;
          } else if (diaRegistro <= 14) {
            semanaNum = 2;
          } else if (diaRegistro <= 21) {
            semanaNum = 3;
          } else if (diaRegistro <= 28) {
            semanaNum = 4;
          } else {
            semanaNum = 5;
          }

          final claveSemana = 'semana_$semanaNum';
          porSemana.putIfAbsent(claveSemana, () => []).add({
            'fecha': fechaStr,
            'horasExtrasMin': minutos,
            'esSabado': item['es_sabado'] as bool? ?? false,
            'horaFin': horaFin,
            'dia': diaRegistro,
            'mes': mesRegistro,
            'anno': annoRegistro,
          });
        }

        // Convertir agrupación por semana a lista de semanas
        for (final entry in porSemana.entries) {
          final diasSemana = entry.value;
          final totalSemana = diasSemana.fold<int>(0, (sum, d) => sum + (d['horasExtrasMin'] as int));
          
          // Ordenar días de la semana por fecha
          diasSemana.sort((a, b) => (a['dia'] as int).compareTo(b['dia'] as int));
          
          final primerDia = diasSemana.first;
          final mesSemana = primerDia['mes'] as int;
          final annoSemana = primerDia['anno'] as int;
          
          // Extraer número de semana de la clave (ej: "semana_1" -> 1)
          final semanaNum = int.tryParse(entry.key.split('_').last) ?? 1;
          
          // Calcular inicio y fin de semana
          final inicioSemana = semanaNum == 1 ? 1 : (semanaNum - 1) * 7 + 1;
          final finSemana = semanaNum == 5 
              ? DateTime(annoSemana, mesSemana + 1, 0).day // Último día del mes
              : semanaNum * 7;
          
          detalleHorasExtras.add({
            'tipo': 'semana',
            'inicioSemana': inicioSemana,
            'finSemana': finSemana,
            'mes': mesSemana,
            'anno': annoSemana,
            'totalMinutos': totalSemana,
            'dias': diasSemana,
          });
        }

        // Ordenar semanas por número descendente
        detalleHorasExtras.sort((a, b) {
          final semanaA = a['inicioSemana'] as int;
          final semanaB = b['inicioSemana'] as int;
          return semanaB.compareTo(semanaA);
        });
      } catch (e) {
        print('❌ [Tiempo] Error obteniendo horas extras: $e');
      }

      // Tiempo sin actividad = Inicio tardío + Fin temprano
      final tiempoSinActividad = tiempoInicioTardioTotal + tiempoFinTempranoTotal;

      // Promedios
      final tiempoPromedioOrden = ordenesMes.isNotEmpty
          ? (tiempoTrabajoTotal / ordenesMes.length).round()
          : 0;

      final ordenesPorDia = diasTrabajados > 0
          ? ordenesMes.length / diasTrabajados
          : 0.0;

      // Productividad = Trabajo efectivo / Tiempo productivo esperado
      final productividad = tiempoProductivoEsperado > 0
          ? (tiempoTrabajoTotal / tiempoProductivoEsperado) * 100
          : 0.0;

      // Promedio de inicio tardío por día
      final promedioInicioTardio = diasTrabajados > 0
          ? (tiempoInicioTardioTotal / diasTrabajados).round()
          : 0;

      print('⏱️ [Tiempo] Días L-V: $diasSemana, Sábados: $diasSabado');
      print('⏱️ [Tiempo] Trabajo: ${tiempoTrabajoTotal}min (${(tiempoTrabajoTotal/60).toStringAsFixed(1)}h)');
      print('⏱️ [Tiempo] Esperado: ${tiempoProductivoEsperado}min (${(tiempoProductivoEsperado/60).toStringAsFixed(1)}h)');
      print('⏱️ [Tiempo] Trayecto/Espera: ${tiempoTrayectoTotal}min');
      print('⏱️ [Tiempo] Inicio tardío: ${tiempoInicioTardioTotal}min, Fin temprano: ${tiempoFinTempranoTotal}min');
      print('⏱️ [Tiempo] Productividad: ${productividad.toStringAsFixed(1)}%');

      return {
        'tiempoTrabajoTotal': tiempoTrabajoTotal,
        'tiempoTrayectoTotal': tiempoTrayectoTotal,
        'tiempoInicioTardio': tiempoInicioTardioTotal,
        'tiempoFinTemprano': tiempoFinTempranoTotal,
        'tiempoSinActividad': tiempoSinActividad,
        'tiempoPromedioOrden': tiempoPromedioOrden,
        'promedioInicioTardio': promedioInicioTardio,
        'productividad': productividad,
        'diasTrabajados': diasTrabajados,
        'diasSemana': diasSemana,
        'diasSabado': diasSabado,
        'ordenesPorDia': ordenesPorDia,
        'tiempoProductivoEsperado': tiempoProductivoEsperado,
        'detalleInicioTardio': detalleInicioTardio,
        'horasExtrasTotal': horasExtrasTotal,
        'detalleHorasExtras': detalleHorasExtras,
      };
    } catch (e) {
      print('❌ [Produccion] Error obteniendo métricas de tiempo: $e');
      return _metricasTiempoVacias();
    }
  }

  Map<String, dynamic> _metricasTiempoVacias() {
    return {
      'tiempoTrabajoTotal': 0,
      'tiempoTrayectoTotal': 0,
      'tiempoInicioTardio': 0,
      'tiempoFinTemprano': 0,
      'tiempoSinActividad': 0,
      'tiempoPromedioOrden': 0,
      'promedioInicioTardio': 0,
      'productividad': 0.0,
      'diasTrabajados': 0,
      'diasSemana': 0,
      'diasSabado': 0,
      'ordenesPorDia': 0.0,
      'tiempoProductivoEsperado': 0,
      'detalleInicioTardio': <Map<String, dynamic>>[],
      'horasExtrasTotal': 0,
      'detalleHorasExtras': <Map<String, dynamic>>[],
    };
  }

  /// Devuelve el primer valor no vacío de las llaves candidatas
  String _pickFirstNonEmpty(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty && s.toLowerCase() != 'null') {
        return s;
      }
    }
    return '';
  }

  /// Parsear hora "HH:MM" a minutos desde medianoche
  int _parseHoraAMinutos(String hora) {
    try {
      final partes = hora.split(':');
      if (partes.length >= 2) {
        final h = int.parse(partes[0]);
        final m = int.parse(partes[1]);
        return h * 60 + m;
      }
    } catch (e) {
      // Ignorar errores de parseo
    }
    return 0;
  }

  /// Formatear minutos a string "Xh Xm"
  static String formatearMinutos(int minutos) {
    if (minutos <= 0) return '0m';
    final horas = minutos ~/ 60;
    final mins = minutos % 60;
    if (horas > 0 && mins > 0) return '${horas}h ${mins}m';
    if (horas > 0) return '${horas}h';
    return '${mins}m';
  }

  // ═══════════════════════════════════════════════════════════
  // MÉTRICAS DE CALIDAD
  // ═══════════════════════════════════════════════════════════

  /// Obtener métricas de calidad del técnico desde v_calidad_tecnicos
  /// Retorna un mapa compatible con el formato anterior para mantener compatibilidad
  Future<Map<String, dynamic>> obtenerCalidadMes(
    String rutTecnico, {
    int? mes,
    int? anno,
  }) async {
    try {
      // Consultar vista v_calidad_tecnicos
      final response = await _supabase
          .from('v_calidad_tecnicos')
          .select()
          .eq('rut_tecnico', rutTecnico)
          .maybeSingle();

      if (response == null) {
        // Técnico sin reiterados
        return {
          'reiteracion': 0.0,
          'completadas': 0,
          'reiterados': 0,
          'totalReiterados': 0,
          'promedioDias': 0.0,
          'calidadTecnico': null,
          'ordenesReiteradas': <Map<String, dynamic>>[],
          'ordenesCompletadas': <Map<String, dynamic>>[],
          'periodo': '',
        };
      }

      final calidadTecnico = CalidadTecnico.fromJson(response);
      
      // Calcular porcentaje de reiteración (mantener compatibilidad)
      // Nota: La vista ya calcula total_reiterados, pero necesitamos completadas
      // para el porcentaje. Por ahora usamos total_reiterados como base.
      final reiteracion = calidadTecnico.totalReiterados > 0
          ? (calidadTecnico.totalReiterados / (calidadTecnico.totalReiterados + 50)) * 100
          : 0.0; // Aproximación, ya que no tenemos completadas en la vista

      print('📊 [Calidad] Total reiterados: ${calidadTecnico.totalReiterados}');
      print('📊 [Calidad] Promedio días: ${calidadTecnico.promedioDias}');
      print('📊 [Calidad] Reiteración: ${reiteracion.toStringAsFixed(1)}%');

      return {
        'reiteracion': reiteracion,
        'completadas': calidadTecnico.totalReiterados + 50, // Aproximación
        'reiterados': calidadTecnico.totalReiterados,
        'totalReiterados': calidadTecnico.totalReiterados,
        'promedioDias': calidadTecnico.promedioDias,
        'calidadTecnico': calidadTecnico,
        'ordenesReiteradas': <Map<String, dynamic>>[],
        'ordenesCompletadas': <Map<String, dynamic>>[],
        'periodo': '',
      };
    } catch (e, stackTrace) {
      print('❌ [Calidad] Error: $e');
      print('❌ [Calidad] StackTrace: $stackTrace');
        return {
          'reiteracion': 0.0,
          'completadas': 0,
          'reiterados': 0,
        'totalReiterados': 0,
        'promedioDias': 0.0,
        'calidadTecnico': null,
          'ordenesReiteradas': <Map<String, dynamic>>[],
          'ordenesCompletadas': <Map<String, dynamic>>[],
        'periodo': '',
      };
    }
  }

  /// Obtener detalle de reiterados desde calidad_traza
  Future<List<DetalleReiterado>> obtenerDetalleReiterados(String rutTecnico) async {
    try {
      print('📋 [Detalle] Consultando calidad_traza para RUT=$rutTecnico');
      
      // Obtener TODOS los reiterados sin límite
      final response = await _supabase
          .from('calidad_traza')
          .select('*')
          .eq('rut_tecnico_original', rutTecnico)
          .order('fecha_original', ascending: false);

      final lista = List<Map<String, dynamic>>.from(response as List);
      print('📋 [Detalle] ✅ ${lista.length} reiterados encontrados en total');
      
      return lista.map((item) => DetalleReiterado.fromJson(item)).toList();
    } catch (e) {
      print('❌ [Calidad] Error obteniendo detalle reiterados: $e');
      return [];
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════════
  /// MÉTODOS PARA CALIDAD (basados en garantías que terminan el día 20)
  /// ═══════════════════════════════════════════════════════════════════════════
  
  /// Obtener período CERRADO de Calidad (garantía ya venció)
  /// Ejemplo: Hoy 3 ENE → CERRADO = DIC (garantía terminó el 20 dic)
  /// Ejemplo: Hoy 25 ENE → CERRADO = ENE (garantía terminó el 20 ene)
  String getPeriodoCerrado() {
    final now = DateTime.now();
    if (now.day > 20) {
      // Si pasó el día 20, el período actual ya está cerrado
      return '${now.year}-${now.month.toString().padLeft(2, '0')}';
    } else {
      // Si estamos antes del 20, el período cerrado es el mes anterior
      final mesMenos = DateTime(now.year, now.month - 1, 1);
      return '${mesMenos.year}-${mesMenos.month.toString().padLeft(2, '0')}';
    }
  }

  /// Obtener período ACTUAL de Calidad (garantía en curso, midiendo)
  /// Ejemplo: Hoy 3 ENE → ACTUAL = ENE (garantía hasta el 20 ene, midiendo)
  /// Ejemplo: Hoy 25 ENE → ACTUAL = FEB (garantía hasta el 20 feb, midiendo)
  String getPeriodoActual() {
    final now = DateTime.now();
    if (now.day > 20) {
      // Si pasó el día 20, el período actual es el mes siguiente
      final mesMas = DateTime(now.year, now.month + 1, 1);
      return '${mesMas.year}-${mesMas.month.toString().padLeft(2, '0')}';
    } else {
      // Si estamos antes del 20, el período actual es este mes
      return '${now.year}-${now.month.toString().padLeft(2, '0')}';
    }
  }

  /// Obtener período ANTERIOR de Calidad (para histórico)
  /// Ejemplo: Hoy 3 ENE → ANTERIOR = no se usa en UI principal
  String getPeriodoAnterior() {
    final now = DateTime.now();
    if (now.day > 20) {
      // Si pasó el día 20, el período anterior es este mes
      return '${now.year}-${now.month.toString().padLeft(2, '0')}';
    } else {
      // Si estamos antes del 20, el período anterior es mes - 2
      final mesMenos2 = DateTime(now.year, now.month - 2, 1);
      return '${mesMenos2.year}-${mesMenos2.month.toString().padLeft(2, '0')}';
    }
  }
  
  /// Obtener período SIGUIENTE de Calidad (también midiendo)
  /// Ejemplo: Hoy 3 ENE → SIGUIENTE = FEB (garantía hasta el 20 feb, también midiendo)
  String getPeriodoSiguiente() {
    final now = DateTime.now();
    if (now.day > 20) {
      // Si pasó el día 20, el período siguiente es mes + 2
      final mesMas2 = DateTime(now.year, now.month + 2, 1);
      return '${mesMas2.year}-${mesMas2.month.toString().padLeft(2, '0')}';
    } else {
      // Si estamos antes del 20, el período siguiente es mes + 1
      final mesMas = DateTime(now.year, now.month + 1, 1);
      return '${mesMas.year}-${mesMas.month.toString().padLeft(2, '0')}';
    }
  }

  /// Obtener calidad del técnico para múltiples períodos desde calidad_api_script
  Future<Map<String, dynamic>> obtenerCalidadPeriodos(String rutTecnico) async {
    try {
      final periodoCerrado = getPeriodoCerrado();
      final periodoActual = getPeriodoActual();
      final periodoSiguiente = getPeriodoSiguiente();

      print('📊 [Calidad] RUT: $rutTecnico');
      print('📊 [Calidad] Períodos YYYY-MM → cerrado=$periodoCerrado, actual=$periodoActual, siguiente=$periodoSiguiente');

      // Calidad API usa formato "MM-YYYY"
      final apiCerrado  = _convertirPeriodo(periodoCerrado);
      final apiActual   = _convertirPeriodo(periodoActual);
      final apiSiguiente = _convertirPeriodo(periodoSiguiente);

      final response = await _supabase
          .from('calidad_api_script')
          .select('rut_o_bucket, estado, es_reiterado, periodo')
          .eq('rut_o_bucket', rutTecnico)
          .inFilter('periodo', [apiCerrado, apiActual, apiSiguiente]);

      final lista = List<Map<String, dynamic>>.from(response as List);
      print('📊 [Calidad] Registros encontrados en calidad_api_script: ${lista.length}');

      // Acumular por período
      Map<String, Map<String, int>> acum = {};
      for (var item in lista) {
        final p = item['periodo']?.toString() ?? '';
        acum.putIfAbsent(p, () => {'total': 0, 'reit': 0});
        if (item['estado']?.toString() == 'Completado') acum[p]!['total'] = acum[p]!['total']! + 1;
        if (item['es_reiterado'] == true) acum[p]!['reit'] = acum[p]!['reit']! + 1;
      }

      Map<String, dynamic>? _buildMap(String periodoInterno, String apiPeriodo) {
        final d = acum[apiPeriodo];
        if (d == null) return null;
        final total = d['total']!;
        final reit  = d['reit']!;
        return {
          'periodo': periodoInterno,
          'total_completadas': total,
          'total_reiterados': reit,
          'porcentaje_reiteracion': total > 0 ? (reit / total) * 100.0 : 0.0,
          'promedio_dias': 0.0,
        };
      }

      final cerrado  = _buildMap(periodoCerrado, apiCerrado);
      final actual   = _buildMap(periodoActual, apiActual);
      final siguiente = _buildMap(periodoSiguiente, apiSiguiente);

      print('📊 [Calidad] cerrado=${cerrado != null ? "✅ ${cerrado['total_reiterados']} reit / ${cerrado['total_completadas']}" : "❌"}');
      print('📊 [Calidad] actual=${actual != null ? "✅ ${actual['total_reiterados']} reit / ${actual['total_completadas']}" : "❌"}');

      return {
        'cerrado': cerrado,
        'actual': actual,
        'anterior': siguiente,
        'periodo_cerrado': periodoCerrado,
        'periodo_actual': periodoActual,
        'periodo_anterior': periodoSiguiente,
      };
    } catch (e) {
      print('❌ [Calidad] Error obteniendo calidad por períodos: $e');
      return {
        'cerrado': null,
        'actual': null,
        'anterior': null,
        'periodo_cerrado': getPeriodoCerrado(),
        'periodo_actual': getPeriodoActual(),
        'periodo_anterior': getPeriodoSiguiente(),
      };
    }
  }

  /// Obtener color según porcentaje de reiterados
  Color getColorCalidad(double porcentaje) {
    if (porcentaje <= 4.0) return Colors.green;      // Excelente (≤ 4%)
    if (porcentaje <= 5.7) return Colors.orange;      // Regular (4.1% - 5.7%)
    return Colors.red;                                 // Necesita mejorar (> 5.8%)
  }

  /// Obtener calidad del técnico para un período específico desde calidad_api_script
  Future<Map<String, dynamic>?> obtenerCalidadPorPeriodo(String rutTecnico, String periodo) async {
    try {
      // periodo puede venir como "YYYY-MM" o "MM-YYYY"; normalizar a "MM-YYYY"
      final periodoApi = periodo.contains('-') && periodo.split('-')[0].length == 4
          ? _convertirPeriodo(periodo)
          : periodo;

      final response = await _supabase
          .from('calidad_api_script')
          .select('estado, es_reiterado, periodo')
          .eq('rut_o_bucket', rutTecnico)
          .eq('periodo', periodoApi);

      final lista = List<Map<String, dynamic>>.from(response as List);
      if (lista.isEmpty) return null;

      final completadas = lista.where((o) => o['estado']?.toString() == 'Completado').length;
      final reiterados  = lista.where((o) => o['es_reiterado'] == true).length;

      return {
        'periodo': periodo,
        'total_completadas': completadas,
        'total_reiterados': reiterados,
        'porcentaje_reiteracion': completadas > 0 ? (reiterados / completadas) * 100.0 : 0.0,
        'promedio_dias': 0.0,
      };
    } catch (e) {
      print('❌ [Calidad] Error obteniendo calidad por período: $e');
      return null;
    }
  }

  /// Obtener período desde mes y año
  String getPeriodoDesdeMesAnno(int mes, int anno) {
    return '$anno-${mes.toString().padLeft(2, '0')}';
  }

  /// Obtener nombre del mes desde período
  String getNombreMes(String periodo) {
    try {
      final partes = periodo.split('-');
      if (partes.length == 2) {
        final mes = int.parse(partes[1]);
        const meses = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
        if (mes >= 1 && mes <= 12) {
          return meses[mes];
        }
      }
    } catch (e) {
      print('⚠️ [Calidad] Error obteniendo nombre del mes: $e');
    }
    return '';
  }

  /// Obtener detalle de reiterados desde calidad_api_script (es_reiterado = true)
  Future<List<Map<String, dynamic>>> obtenerDetalleReiteradosPorPeriodo(
    String rutTecnico,
    String periodo,
  ) async {
    try {
      // periodo puede venir como "YYYY-MM" o "MM-YYYY"
      final periodoApi = periodo.contains('-') && periodo.split('-')[0].length == 4
          ? _convertirPeriodo(periodo)
          : periodo;

      print('📋 [Detalle] calidad_api_script RUT=$rutTecnico periodo=$periodoApi');

      final response = await _supabase
          .from('calidad_api_script')
          .select()
          .eq('rut_o_bucket', rutTecnico)
          .eq('periodo', periodoApi)
          .eq('es_reiterado', true)
          .order('fecha', ascending: false);

      final lista = List<Map<String, dynamic>>.from(response as List);
      print('📋 [Detalle] ✅ ${lista.length} reiterados encontrados');
      return lista;
    } catch (e) {
      print('❌ [Calidad] Error obteniendo detalle de reiterados: $e');
      return [];
    }
  }

  /// Calcular rango de fechas de TRABAJO para un período
  /// Ejemplo: período "2025-11" (BONO NOV) → trabajo del 21 SEP al 20 OCT
  Map<String, String> _calcularRangoFechasTrabajo(String periodo) {
    try {
      final partes = periodo.split('-');
      if (partes.length == 2) {
        int anno = int.parse(partes[0]);
        int mes = int.parse(partes[1]);
        
        // Fecha inicio: día 21 del mes (periodo - 2)
        // Período 2025-11 → inicio 21 de SEP (mes 9)
        int mesInicio = mes - 2;
        int annoInicio = anno;
        if (mesInicio < 1) {
          mesInicio = 12 + mesInicio;
          annoInicio -= 1;
        }
        
        final fechaInicio = '$annoInicio-${mesInicio.toString().padLeft(2, '0')}-21';
        
        // Fecha fin: día 20 del mes (periodo - 1)
        // Período 2025-11 → fin 20 de OCT (mes 10)
        int mesFin = mes - 1;
        int annoFin = anno;
        if (mesFin < 1) {
          mesFin = 12;
          annoFin -= 1;
        }
        
        final fechaFin = '$annoFin-${mesFin.toString().padLeft(2, '0')}-20';
        
        return {
          'inicio': fechaInicio,
          'fin': fechaFin,
        };
      }
    } catch (e) {
      print('⚠️ Error calculando rango de fechas: $e');
    }
    
        return {
      'inicio': '2000-01-01',
      'fin': '2099-12-31',
    };
  }

  /// Calcular el siguiente mes para el filtro de rango
  String _calcularSiguienteMes(String periodo) {
    try {
      final partes = periodo.split('-');
      if (partes.length == 2) {
        int anno = int.parse(partes[0]);
        int mes = int.parse(partes[1]);
        
        mes += 1;
        if (mes > 12) {
          mes = 1;
          anno += 1;
        }
        
        return '$anno-${mes.toString().padLeft(2, '0')}-01';
      }
    } catch (e) {
      print('⚠️ Error calculando siguiente mes: $e');
    }
    return '2099-12-31'; // Fecha lejana como fallback
  }

  /// Formatear fecha desde formato "2025-11-20" a "20/11/2025"
  String formatearFecha(String? fecha) {
    if (fecha == null || fecha.isEmpty) return '';
    try {
      final partes = fecha.split('-');
      if (partes.length == 3) {
        return '${partes[2]}/${partes[1]}/${partes[0]}';
      }
    } catch (e) {
      print('⚠️ [Calidad] Error formateando fecha: $e');
    }
    return fecha;
  }

  /// Obtener ranking de calidad para un período desde calidad_api_script
  Future<Map<String, dynamic>> obtenerRankingCalidad(String periodo) async {
    try {
      final periodoApi = periodo.contains('-') && periodo.split('-')[0].length == 4
          ? _convertirPeriodo(periodo)
          : periodo;
      print('🏆 [Calidad] Ranking para período: $periodoApi');

      // Obtener completadas del período
      final responseComp = await _supabase
          .from('calidad_api_script')
          .select('rut_o_bucket, tecnico, es_reiterado')
          .eq('periodo', periodoApi)
          .eq('estado', 'Completado')
          .limit(10000);

      final listaComp = List<Map<String, dynamic>>.from(responseComp as List);
      print('🏆 [Calidad] Completadas para ranking: ${listaComp.length} (periodo=$periodoApi)');

      // Agrupar por técnico contando completadas y reiterados
      final Map<String, Map<String, dynamic>> porTecnico = {};
      for (var item in listaComp) {
        final rut = item['rut_o_bucket']?.toString() ?? '';
        if (rut.isEmpty) continue;
        porTecnico.putIfAbsent(rut, () => {
          'rut_tecnico': rut,
          'tecnico': item['tecnico']?.toString() ?? rut,
          'total_completadas': 0,
          'total_reiterados': 0,
        });
        porTecnico[rut]!['total_completadas'] =
            (porTecnico[rut]!['total_completadas'] as int) + 1;

        // Aceptar es_reiterado como bool true, int 1, o string 'true'
        final esReit = item['es_reiterado'];
        if (esReit == true || esReit == 1 || esReit.toString() == 'true') {
          porTecnico[rut]!['total_reiterados'] =
              (porTecnico[rut]!['total_reiterados'] as int) + 1;
        }
      }

      // Calcular porcentajes y ordenar (menor = mejor)
      final tecnicos = porTecnico.values.map((t) {
        final total = t['total_completadas'] as int;
        final reit  = t['total_reiterados'] as int;
        return <String, dynamic>{
          ...t,
          'porcentaje_reiteracion': total > 0 ? (reit / total) * 100.0 : 0.0,
          'promedio_dias': 0.0,
        };
      }).toList();

      tecnicos.sort((a, b) =>
          (a['porcentaje_reiteracion'] as double)
              .compareTo(b['porcentaje_reiteracion'] as double));

      for (int i = 0; i < tecnicos.length; i++) {
        tecnicos[i]['posicion'] = i + 1;
      }

      print('🏆 [Calidad] Ranking tiene ${tecnicos.length} técnicos');
      return {'ranking': tecnicos, 'totalTecnicos': tecnicos.length};
    } catch (e) {
      print('❌ [Calidad] Error obteniendo ranking: $e');
      return {'ranking': [], 'totalTecnicos': 0};
    }
  }

  /// Obtener posición del técnico en ranking de calidad
  Future<Map<String, dynamic>> obtenerPosicionCalidad(
    String rutTecnico,
    String periodo,
  ) async {
    try {
      print('🎯 [Calidad] Buscando posición para RUT: $rutTecnico en período: $periodo');

      final rankingData = await obtenerRankingCalidad(periodo);
      final ranking = List<Map<String, dynamic>>.from(rankingData['ranking'] as List);

      Map<String, dynamic>? tecnicoEncontrado;
      for (var t in ranking) {
        if (t['rut_tecnico'] == rutTecnico) {
          tecnicoEncontrado = t;
          break;
        }
      }

      if (tecnicoEncontrado == null) {
        return {
          'posicion': 0,
          'totalTecnicos': ranking.length,
          'porcentajeReiterados': 0.0,
          'totalReiterados': 0,
          'totalCompletadas': 0,
          'promedioDias': 0.0,
          'top10': ranking,
        };
      }

      return {
        'posicion': tecnicoEncontrado['posicion'],
        'totalTecnicos': ranking.length,
        'porcentajeReiterados':
            (tecnicoEncontrado['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0,
        'totalReiterados':
            (tecnicoEncontrado['total_reiterados'] as num?)?.toInt() ?? 0,
        'totalCompletadas':
            (tecnicoEncontrado['total_completadas'] as num?)?.toInt() ?? 0,
        'promedioDias': 0.0,
        'nombre': tecnicoEncontrado['tecnico'],
        'top10': ranking,
      };
    } catch (e) {
      print('❌ [Calidad] Error obteniendo posición: $e');
      return {
        'posicion': 0,
        'totalTecnicos': 0,
        'porcentajeReiterados': 0.0,
        'totalReiterados': 0,
        'totalCompletadas': 0,
        'promedioDias': 0.0,
        'top10': [],
      };
    }
  }
}

