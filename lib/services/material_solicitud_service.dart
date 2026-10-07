import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:trazabox/config/constants.dart';
import 'package:trazabox/models/solicitud_material.dart';
import 'package:trazabox/services/logistica_service.dart';
import 'package:trazabox/services/traza_consumo_service.dart';
import 'package:trazabox/services/traza_proxy_service.dart';

/// Resultado del traspaso técnico→técnico en el ERP traza materiales.
class ResultadoTraspasoErp {
  final bool ok;
  final int? traspasoId;
  final String detalle;

  const ResultadoTraspasoErp({
    required this.ok,
    this.traspasoId,
    this.detalle = '',
  });
}

class ResultadoNotificacionDestinatarios {
  const ResultadoNotificacionDestinatarios({
    required this.cantidad,
    this.keplerDisponible = true,
  });

  final int cantidad;
  final bool keplerDisponible;

  bool get sinDestinatarios => cantidad == 0;
}

class MaterialSolicitudService {
  final _db = Supabase.instance.client;

  static const _fcmTimeout = Duration(seconds: 8);

  Future<void> _enviarFcmMaterial({
    required List<String> ruts,
    required String solicitudId,
    required String tipoMaterial,
  }) async {
    if (ruts.isEmpty) return;
    try {
      final tokenRows = await _db
          .from('tecnicos_traza_zc')
          .select('rut, fcm_token')
          .inFilter('rut', ruts);
      final tokens = <String>[];
      for (final row in tokenRows as List) {
        final token = row['fcm_token']?.toString() ?? '';
        if (token.isNotEmpty) tokens.add(token);
      }
      if (tokens.isEmpty) return;
      await _db.functions.invoke('fcm-send', body: {
        if (tokens.length == 1) 'token': tokens.first else 'tokens': tokens,
        'accion': 'solicitud_material',
        'title': '¡Solicitud de material!',
        'tipo': '¡Solicitud de material!',
        'body': 'Se necesita: $tipoMaterial',
        'descripcion': 'Se necesita: $tipoMaterial',
        'solicitud_id': solicitudId,
        'data_only': true,
        'skip_notification': true,
        'android_channel_id': 'mat_alertas_7',
        'android_priority': 'high',
      }).timeout(_fcmTimeout);
      debugPrint('✅ [Material] FCM → ${tokens.length} dispositivo(s)');
    } catch (e) {
      debugPrint('⚠️ [Material] FCM falló: $e');
    }
  }

  static bool _ubicacionVigente(String? updatedAt) {
    if (updatedAt == null || updatedAt.isEmpty) return false;
    try {
      final t = DateTime.parse(updatedAt).toUtc();
      final maxAntiguedad = Duration(
        minutes: kMaterialGpsMaxAntiguedadMinutos,
      );
      return DateTime.now().toUtc().difference(t) <= maxAntiguedad;
    } catch (_) {
      return false;
    }
  }

  /// Umbral mínimo de stock para que un técnico pueda compartir sin
  /// quedarse corto (equipos con resguardo; ferretería basta con 1).
  static double _umbralStock(String tipoMaterial) {
    if (tipoMaterial.contains('ONT') ||
        tipoMaterial.contains('Decodificador')) {
      return 3.0;
    }
    if (tipoMaterial.contains('Extensor')) return 2.0;
    return 0.0;
  }

  /// Máximo de candidatos cercanos a los que se les consulta inventario
  /// (la API traza es por RUT: una llamada por candidato).
  static const _maxCandidatosStock = 15;

  /// Encuentra técnicos cercanos con GPS vigente, verifica su stock REAL en
  /// traza materiales (solo para los más cercanos) y los notifica.
  /// Si la API traza no responde, bypass: notifica por GPS con stock
  /// desconocido (-1).
  Future<ResultadoNotificacionDestinatarios> notificarDestinatarios({
    required String solicitudId,
    required String tipoMaterial,
    required double? latSolicitante,
    required double? lngSolicitante,
    required String rutSolicitante,
    bool soloRadio5Km = true,
  }) async {
    List<dynamic> ubicRows;
    try {
      ubicRows = await _db
          .from('tecnicos_ubicacion')
          .select('tecnico_id, latitud, longitud, en_linea, ultima_actualizacion');
    } catch (e) {
      debugPrint('⚠️ [Material] error ubicaciones: $e');
      return const ResultadoNotificacionDestinatarios(cantidad: 0);
    }

    // No notificar a supervisores
    Set<String> supervisores = {};
    try {
      final supRows =
          await _db.from('supervisores_traza').select('rut').eq('activo', true);
      supervisores = (supRows as List)
          .map((r) => LogisticaService.normalizeRutKey(r['rut'] as String? ?? ''))
          .toSet();
    } catch (_) {}

    final Map<String, (double, double)> ubicMap = {};
    for (final u in ubicRows) {
      final rut = u['tecnico_id'] as String?;
      if (rut == null || rut.isEmpty) continue;
      if (u['en_linea'] != true) continue;
      if (!_ubicacionVigente(u['ultima_actualizacion'] as String?)) continue;
      final lat = (u['latitud'] as num?)?.toDouble();
      final lng = (u['longitud'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      if (lat.abs() < 0.0001 && lng.abs() < 0.0001) continue;
      if (LogisticaService.sameRut(rut, rutSolicitante)) continue;
      if (supervisores.contains(LogisticaService.normalizeRutKey(rut))) {
        continue;
      }
      ubicMap[rut] = (lat, lng);
    }

    final aplicarRadio = soloRadio5Km && kMaterialFiltroDistanciaActivo;

    // 1. Cercanía primero (barato): candidatos por GPS ordenados por distancia
    final cercanos = <({String rut, double dist})>[];
    for (final entry in ubicMap.entries) {
      double dist = 0;
      if (latSolicitante != null && lngSolicitante != null) {
        dist = _distanciaKm(
            latSolicitante, lngSolicitante, entry.value.$1, entry.value.$2);
        if (aplicarRadio && dist > kMaterialRadioKm) continue;
      }
      cercanos.add((rut: entry.key, dist: dist));
    }
    cercanos.sort((a, b) => a.dist.compareTo(b.dist));
    final aConsultar = cercanos.take(_maxCandidatosStock).toList();

    // 2. Stock real en traza materiales, solo para los cercanos.
    // Regla: si no se puede verificar el stock de un técnico, NO se le
    // notifica (nunca avisar a alguien que no tiene el material).
    final umbral = _umbralStock(tipoMaterial);
    final consumo = TrazaConsumoService();
    var trazaDisponible = true;

    final destinatarios = <Map<String, dynamic>>[];
    for (final c in aConsultar) {
      int? stockDisp;
      // Reintentos con pausa: la API traza tiene rate-limit (Cloudflare)
      for (var intento = 0; intento < 3; intento++) {
        try {
          final stock = await consumo.obtenerStock(c.rut);
          stockDisp = stock.porCategoria[tipoMaterial] ?? 0;
          break;
        } catch (e) {
          debugPrint(
              '⚠️ [MatDest] ${c.rut} intento ${intento + 1} falló: $e');
          if (intento < 2) {
            await Future<void>.delayed(Duration(seconds: 2 + intento * 3));
          }
        }
      }
      if (stockDisp == null) {
        trazaDisponible = false;
        debugPrint(
            '[MatDest] ${c.rut} → stock no verificable, no se notifica');
        continue;
      }
      if (stockDisp <= umbral) {
        debugPrint(
            '[MatDest] ${c.rut} → stock insuficiente ($tipoMaterial=$stockDisp ≤ $umbral)');
        continue;
      }
      // Ritmo entre candidatos para no gatillar el rate-limit
      await Future<void>.delayed(const Duration(milliseconds: 400));

      String nombre = c.rut;
      try {
        final row = await _db
            .from('plantel_tecnicos')
            .select('nombre_completo')
            .eq('rut', c.rut)
            .maybeSingle();
        final n = row?['nombre_completo'] as String? ?? '';
        if (n.isNotEmpty) nombre = n;
      } catch (_) {}

      destinatarios.add({
        'solicitud_id': solicitudId,
        'rut_tecnico': c.rut,
        'nombre_tecnico': nombre,
        'stock_disponible': stockDisp,
        'estado': 'pendiente',
      });
    }

    if (destinatarios.isEmpty) {
      return ResultadoNotificacionDestinatarios(
        cantidad: 0,
        keplerDisponible: trazaDisponible,
      );
    }

    await _db.from('solicitudes_material_destinatarios').insert(destinatarios);

    await _enviarFcmMaterial(
      ruts: destinatarios
          .map((d) => d['rut_tecnico'] as String)
          .toList(),
      solicitudId: solicitudId,
      tipoMaterial: tipoMaterial,
    );

    for (final d in destinatarios) {
      try {
        await _db.from('alertas_fcm').upsert({
          'rut_tecnico': d['rut_tecnico'],
          'activa': true,
          'tipo': 'solicitud_material',
          'descripcion': 'Solicitud de material: $tipoMaterial',
        }, onConflict: 'rut_tecnico');
      } catch (_) {}
    }

    return ResultadoNotificacionDestinatarios(
      cantidad: destinatarios.length,
      keplerDisponible: trazaDisponible,
    );
  }

  // ── Traspaso en el ERP traza materiales ───────────────────────────────────

  /// Ejecuta el traspaso técnico→técnico en el ERP (fuente de verdad):
  /// descuenta la bodega del entregador y suma en la del solicitante.
  /// Resuelve el SKU real del entregador para la categoría solicitada
  /// (mayor saldo); para seriados usa la serie escaneada.
  Future<ResultadoTraspasoErp> traspasarEnErp({
    required String rutOrigen,
    required String rutDestino,
    required String tipoMaterial,
    required int cantidad,
    required List<String> series,
    String? solicitudId,
  }) async {
    try {
      final stock = await TrazaConsumoService().obtenerStock(rutOrigen);

      // ── Candado persistente: ¿un intento anterior ya descontó? ──
      // Si la solicitud guarda un snapshot de control (se escribe justo
      // antes de cada POST) y el saldo/series del origen ya reflejan el
      // movimiento, el POST anterior entró aunque su respuesta se perdió:
      // NO se repite.
      if (solicitudId != null) {
        final ctl = await _db
            .from('solicitudes_material')
            .select('traspaso_sku_control, traspaso_saldo_control')
            .eq('id', solicitudId)
            .maybeSingle();
        final skuPrev = ctl?['traspaso_sku_control'] as String?;
        final saldoPrev = (ctl?['traspaso_saldo_control'] as num?)?.toInt();
        if (skuPrev != null && saldoPrev != null) {
          bool aplicado;
          if (series.isNotEmpty) {
            final seriesOrigen = stock.items
                .where((i) => i.esSeriado && i.serie != null)
                .map((i) => i.serie)
                .toSet();
            aplicado = series.every((s) => !seriesOrigen.contains(s));
          } else {
            final saldoAhora = stock.items
                .where((i) => i.sku == skuPrev)
                .fold<int>(0, (t, i) => t + i.cantidad);
            aplicado = saldoAhora <= saldoPrev - cantidad;
          }
          if (aplicado) {
            return const ResultadoTraspasoErp(
              ok: true,
              traspasoId: -1,
              detalle: 'Traspaso ya aplicado en un intento anterior '
                  '(confirmado por saldo).',
            );
          }
        }
      }

      final lineas = <Map<String, dynamic>>[];
      if (series.isNotEmpty) {
        // Seriado: una línea por serie, con el SKU dueño de esa serie
        for (final serie in series) {
          ItemStockConsumo? item;
          for (final i in stock.items) {
            if (i.esSeriado && i.serie == serie) {
              item = i;
              break;
            }
          }
          if (item == null) {
            return ResultadoTraspasoErp(
              ok: false,
              detalle:
                  'La serie $serie no está en el inventario del entregador.',
            );
          }
          lineas.add({
            'codigoMaterial': item.sku,
            'cantidad': 1,
            'serie': serie,
          });
        }
      } else {
        // No seriado: SKU con más saldo de la categoría
        final items = stock.items
            .where((i) => !i.esSeriado && i.categoria == tipoMaterial)
            .toList()
          ..sort((a, b) => b.cantidad.compareTo(a.cantidad));
        if (items.isEmpty) {
          return const ResultadoTraspasoErp(
            ok: false,
            detalle: 'El entregador no tiene saldo de esta categoría.',
          );
        }
        lineas.add({
          'codigoMaterial': items.first.sku,
          'cantidad': cantidad,
        });
      }

      // ── Candado anti doble-descuento ────────────────────────────
      // El ERP no es idempotente: si el POST entra pero la respuesta se
      // pierde (red/rate-limit), un reintento descuenta DOS veces. Antes
      // de postear se toma un snapshot del saldo de origen; si la
      // respuesta es ambigua se verifica contra el ERP si el traspaso
      // ya se aplicó, en vez de dejar que el caller reintente a ciegas.
      final skuControl = lineas.first['codigoMaterial'] as String;
      final saldoAntes = stock.items
          .where((i) => i.sku == skuControl)
          .fold<int>(0, (t, i) => t + i.cantidad);

      // Persistir el snapshot ANTES del POST: si la app muere o la
      // respuesta se pierde, el próximo intento lo encuentra y verifica.
      if (solicitudId != null) {
        await _db.from('solicitudes_material').update({
          'traspaso_sku_control': skuControl,
          'traspaso_saldo_control': saldoAntes,
        }).eq('id', solicitudId);
      }

      final n = DateTime.now();
      Object? resp;
      Object? fallo;
      try {
        resp = await TrazaProxyService().post('/traspasos/tecnico-tecnico', {
          'rutOrigen': rutOrigen,
          'rutDestino': rutDestino,
          'fecha':
              '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}',
          'lineas': lineas,
        });
      } catch (e) {
        fallo = e;
      }

      if (fallo != null || resp is! Map) {
        // Respuesta ambigua: el POST pudo haber entrado igual.
        // Verificar contra el saldo actual del origen.
        final aplicado = await _traspasoYaAplicado(
          rutOrigen: rutOrigen,
          skuControl: skuControl,
          saldoAntes: saldoAntes,
          series: series,
          cantidad: cantidad,
        );
        if (aplicado) {
          return const ResultadoTraspasoErp(
            ok: true,
            traspasoId: -1, // sin id: confirmado por verificación de saldo
            detalle: 'Traspaso confirmado por verificación de saldo '
                '(la respuesta del ERP se perdió).',
          );
        }
        return ResultadoTraspasoErp(
          ok: false,
          detalle: fallo != null
              ? 'ERP no contactado: $fallo'
              : 'Respuesta inesperada del ERP (¿bodega inexistente?).',
        );
      }

      final elementos = (resp['elementosCreadosIds'] as List?) ?? [];
      final errores = (resp['errores'] as List?) ?? [];
      if (elementos.isNotEmpty && errores.isEmpty) {
        return ResultadoTraspasoErp(
          ok: true,
          traspasoId: (resp['traspasoId'] as num?)?.toInt(),
          detalle: 'Traspaso registrado en bodega',
        );
      }
      if (elementos.isEmpty && solicitudId != null) {
        // El ERP respondió y no movió nada: limpiar el snapshot de
        // control para que el próximo intento parta de cero.
        await _db.from('solicitudes_material').update({
          'traspaso_sku_control': null,
          'traspaso_saldo_control': null,
        }).eq('id', solicitudId);
      }
      final motivo = errores.isNotEmpty
          ? ((errores.first as Map)['motivo']?.toString() ?? '')
          : 'sin líneas creadas';
      return ResultadoTraspasoErp(
        ok: elementos.isNotEmpty,
        traspasoId: (resp['traspasoId'] as num?)?.toInt(),
        detalle: motivo,
      );
    } catch (e) {
      return ResultadoTraspasoErp(
        ok: false,
        detalle: 'ERP no contactado: $e',
      );
    }
  }

  /// Verifica contra el ERP si un traspaso de respuesta perdida se aplicó
  /// igual: para no seriados el saldo del SKU en origen bajó lo esperado;
  /// para seriados las series ya no están en el origen.
  Future<bool> _traspasoYaAplicado({
    required String rutOrigen,
    required String skuControl,
    required int saldoAntes,
    required List<String> series,
    required int cantidad,
  }) async {
    try {
      // Pequeña espera para que el ERP asiente el movimiento
      await Future<void>.delayed(const Duration(seconds: 3));
      final stock = await TrazaConsumoService().obtenerStock(rutOrigen);
      if (series.isNotEmpty) {
        final seriesOrigen = stock.items
            .where((i) => i.esSeriado && i.serie != null)
            .map((i) => i.serie)
            .toSet();
        return series.every((s) => !seriesOrigen.contains(s));
      }
      final saldoAhora = stock.items
          .where((i) => i.sku == skuControl)
          .fold<int>(0, (t, i) => t + i.cantidad);
      return saldoAhora <= saldoAntes - cantidad;
    } catch (_) {
      // Sin cómo verificar: asumir NO aplicado sería reintentar a ciegas.
      // Preferimos reportar fallo y que el reintento vuelva a pasar por
      // esta misma verificación con la app estable.
      return false;
    }
  }

  // ── PIN de confirmación (prueba de presencia del solicitante) ─────────────

  /// Genera (o reutiliza si sigue vigente) el PIN de 6 dígitos de la
  /// solicitud: lo escribe en la fila —el solicitante lo ve al instante por
  /// realtime— y además lo empuja por FCM como respaldo. 15 min, 3 intentos.
  Future<void> generarPin({
    required String solicitudId,
    required String rutSolicitante,
    bool forzarNuevo = false,
  }) async {
    String? pin;
    if (!forzarNuevo) {
      final row = await _db
          .from('solicitudes_material')
          .select('pin_codigo, pin_expira_en')
          .eq('id', solicitudId)
          .maybeSingle();
      final actual = row?['pin_codigo'] as String?;
      final expiraRaw = row?['pin_expira_en'] as String?;
      final vigente = actual != null &&
          actual.isNotEmpty &&
          expiraRaw != null &&
          DateTime.parse(expiraRaw).isAfter(DateTime.now());
      if (vigente) pin = actual;
    }

    if (pin == null) {
      pin = (100000 + math.Random().nextInt(900000)).toString();
      await _db.from('solicitudes_material').update({
        'pin_codigo': pin,
        'pin_expira_en': DateTime.now()
            .add(const Duration(minutes: 15))
            .toUtc()
            .toIso8601String(),
        'pin_intentos': 3,
      }).eq('id', solicitudId);
    }

    // Respaldo FCM (la vía principal es el realtime de la fila)
    try {
      final tokenRows = await _db
          .from('tecnicos_traza_zc')
          .select('rut, fcm_token')
          .eq('rut', rutSolicitante);
      final token = (tokenRows as List).isNotEmpty
          ? tokenRows.first['fcm_token']?.toString() ?? ''
          : '';
      if (token.isNotEmpty) {
        await _db.functions.invoke('fcm-send', body: {
          'token': token,
          'accion': 'pin_intercambio',
          'title': 'Tu PIN de confirmación',
          'body': 'PIN: $pin — válido 15 minutos',
          'pin': pin,
          'solicitud_id': solicitudId,
          'data_only': true,
          'android_channel_id': 'mat_alertas_7',
        }).timeout(_fcmTimeout);
      }
    } catch (e) {
      debugPrint('⚠️ [PIN] FCM falló (realtime sigue activo): $e');
    }
  }

  /// Correo de respaldo del traspaso (formato agente_desconexiones),
  /// enviado tras la confirmación en el ERP. Nunca bloquea el flujo.
  Future<void> enviarCorreoTraspaso({
    required SolicitudMaterial solicitud,
    required List<String> series,
    int? traspasoErpId,
  }) async {
    try {
      await _db.functions.invoke('email-traspaso-material', body: {
        'solicitud_id': solicitud.id,
        'rut_origen': solicitud.rutEntregador ?? '',
        'nombre_origen': solicitud.nombreEntregador ?? '',
        'rut_destino': solicitud.rutSolicitante,
        'nombre_destino': solicitud.nombreSolicitante,
        'series': series,
        'equipo': solicitud.tipoMaterial,
        'cantidad': solicitud.cantidad,
        'traspaso_erp_id': traspasoErpId,
      }).timeout(const Duration(seconds: 15));
      debugPrint('✅ [Correo] traspaso enviado');
    } catch (e) {
      debugPrint('⚠️ [Correo] falló el envío: $e');
    }
  }

  /// El primer técnico que acepta: cancela los otros destinatarios y actualiza la solicitud.
  Future<void> aceptar({
    required String solicitudId,
    required String rutAceptador,
    required String nombreAceptador,
    required double? lat,
    required double? lng,
  }) async {
    await _db
        .from('solicitudes_material_destinatarios')
        .update({'estado': 'aceptada'})
        .eq('solicitud_id', solicitudId)
        .eq('rut_tecnico', rutAceptador);

    await _db
        .from('solicitudes_material_destinatarios')
        .update({'estado': 'cancelada'})
        .eq('solicitud_id', solicitudId)
        .neq('rut_tecnico', rutAceptador)
        .eq('estado', 'pendiente');

    await _db.from('solicitudes_material').update({
      'estado': 'aceptada',
      'rut_entregador': rutAceptador,
      'nombre_entregador': nombreAceptador,
      'lat_entregador': lat,
      'lng_entregador': lng,
    }).eq('id', solicitudId).eq('estado', 'pendiente');

    // Avisar al solicitante con sonido: su material va en camino
    try {
      final sol = await _db
          .from('solicitudes_material')
          .select('rut_solicitante, tipo_material')
          .eq('id', solicitudId)
          .maybeSingle();
      final rutSol = sol?['rut_solicitante'] as String?;
      if (rutSol != null && rutSol.isNotEmpty) {
        await _fcmARut(
          rut: rutSol,
          accion: 'material_asignada',
          titulo: '¡Material en camino!',
          descripcion:
              '$nombreAceptador va en camino con tu ${sol?['tipo_material'] ?? 'material'}',
          extra: {'solicitud_id': solicitudId},
        );
      }
    } catch (e) {
      debugPrint('⚠️ [Material] FCM material_asignada falló: $e');
    }
  }

  /// Avisa al solicitante que el entregador llegó y se abrirá la guía.
  Future<void> notificarLlegada({
    required String solicitudId,
    required String rutSolicitante,
    required String nombreEntregador,
  }) async {
    await _fcmARut(
      rut: rutSolicitante,
      accion: 'material_llego',
      titulo: '¡Tu material llegó!',
      descripcion:
          '$nombreEntregador está contigo: firma la guía y dicta tu PIN',
      extra: {'solicitud_id': solicitudId},
    );
  }

  /// Envía un FCM data-only (canal con sonido mat_alertas_7) a un RUT.
  Future<void> _fcmARut({
    required String rut,
    required String accion,
    required String titulo,
    required String descripcion,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final rows = await _db
          .from('tecnicos_traza_zc')
          .select('fcm_token')
          .eq('rut', rut);
      final token = (rows as List).isNotEmpty
          ? rows.first['fcm_token']?.toString() ?? ''
          : '';
      if (token.isEmpty) return;
      await _db.functions.invoke('fcm-send', body: {
        'token': token,
        'accion': accion,
        'title': titulo,
        'tipo': titulo,
        'body': descripcion,
        'descripcion': descripcion,
        'data_only': true,
        'skip_notification': true,
        'android_channel_id': 'mat_alertas_7',
        'android_priority': 'high',
        if (extra != null) ...extra,
      }).timeout(_fcmTimeout);
      debugPrint('✅ [Material] FCM $accion → $rut');
    } catch (e) {
      debugPrint('⚠️ [Material] FCM $accion falló: $e');
    }
  }

  Future<List<Map<String, dynamic>>> destinatariosPendientes(
    String solicitudId,
  ) async {
    final rows = await _db
        .from('solicitudes_material_destinatarios')
        .select()
        .eq('solicitud_id', solicitudId)
        .eq('estado', 'pendiente');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  double _distanciaKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _rad(double deg) => deg * math.pi / 180;
}
