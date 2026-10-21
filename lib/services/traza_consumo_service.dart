import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/consumo_reglas.dart';
import '../models/inventario_material.dart';
import 'kepler_sabana_service.dart';
import 'traza_proxy_service.dart';

/// Un ítem concreto del inventario, ya categorizado, listo para la pantalla
/// de consumo. Para seriados se crea un ítem por número de serie.
class ItemStockConsumo {
  final int materialId;
  final String nombre;
  final String sku;
  final String categoria;
  final bool esSeriado;

  /// Cantidad disponible (para seriados siempre 1: un ítem por serie).
  final int cantidad;

  /// Número de serie (solo seriados).
  final String? serie;

  const ItemStockConsumo({
    required this.materialId,
    required this.nombre,
    required this.sku,
    required this.categoria,
    required this.esSeriado,
    required this.cantidad,
    this.serie,
  });
}

/// Stock del técnico agrupado por categorías canónicas de consumo.
class StockConsumoTecnico {
  final String rut;
  final List<ItemStockConsumo> items;

  /// Categoría → saldo total.
  final Map<String, int> porCategoria;

  /// Materiales con stock que no calzaron con ninguna categoría
  /// (no se muestran; sirven para completar las reglas de nombres).
  final List<InventarioMaterial> sinCategoria;

  const StockConsumoTecnico({
    required this.rut,
    required this.items,
    required this.porCategoria,
    required this.sinCategoria,
  });

  bool get vacio => items.isEmpty;
}

/// Orden de trabajo del técnico pendiente de declarar consumo.
/// Sale de la tabla `produccion` (Supabase), no de la API traza.
class OrdenPendienteConsumo {
  final String ordenTrabajo;

  /// true si la OT ya tiene declaración guardada pero el ERP aún no confirma
  /// el descuento (traspaso pendiente/error) → el técnico debe REENVIAR.
  final bool traspasoPendiente;

  /// Tipificación más específica disponible, p. ej. "Alta 2 Play" o
  /// "Modificación de Servicio". Sirve tanto para mostrar como para elegir
  /// la receta (el matcheo es por palabra contenida).
  final String tipoActividad;
  final String fechaTrabajo;
  final String cliente;
  final String direccion;
  final String comuna;

  const OrdenPendienteConsumo({
    required this.ordenTrabajo,
    required this.tipoActividad,
    required this.fechaTrabajo,
    required this.cliente,
    required this.direccion,
    required this.comuna,
    this.traspasoPendiente = false,
  });

  /// Dirección legible para el header ("PJE PEDRO PRADO 238, Buin").
  String get direccionCompleta {
    String limpia(String v) =>
        (v.isEmpty || v == 'Sin Datos' || v == 'NaN') ? '' : v.trim();
    final dir = limpia(direccion);
    final com = limpia(comuna);
    if (dir.isEmpty) return com;
    if (com.isEmpty) return dir;
    return '$dir, $com';
  }
}

class ConsumoResult {
  final bool exito;
  final String mensaje;

  /// Resultado del traspaso en el ERP: ok | parcial | error | pendiente.
  /// El consumo se considera CONFIRMADO solo con ok/parcial.
  final String traspasoEstado;

  const ConsumoResult({
    required this.exito,
    required this.mensaje,
    this.traspasoEstado = 'pendiente',
  });

  bool get confirmadoEnErp =>
      traspasoEstado == 'ok' ||
      traspasoEstado == 'parcial' ||
      traspasoEstado == 'sin_consumo';
}

/// Una orden ya declarada, para el historial de consumos.
class ConsumoDeclarado {
  final String ordenTrabajo;
  final String tipoActividad;

  /// Fecha en que se ejecutó la OT (produccion.fecha_trabajo).
  final String fechaTrabajo;

  /// Momento en que el técnico declaró el consumo.
  final DateTime fechaConsumo;

  /// [{nombre, categoria, cantidad}, ...]
  final List<Map<String, dynamic>> noSeriados;

  /// [{nombre, categoria, serie}, ...]
  final List<Map<String, dynamic>> seriados;

  const ConsumoDeclarado({
    required this.ordenTrabajo,
    required this.tipoActividad,
    required this.fechaTrabajo,
    required this.fechaConsumo,
    required this.noSeriados,
    required this.seriados,
  });

  int get totalItems => noSeriados.length + seriados.length;
}

/// Resumen mensual de consumos declarados (para las cards del historial).
class ResumenMesConsumo {
  final int mes;
  final int anno;
  final int ordenes;
  final int materiales;

  const ResumenMesConsumo({
    required this.mes,
    required this.anno,
    required this.ordenes,
    required this.materiales,
  });
}

/// Resultado del buscador de series (histórico equipos_seriados_traza).
class SerieEncontrada {
  final String serie;
  final String tipoEquipo;
  final String descripcion;
  final String ordenTrabajo;
  final String rutTecnico;
  final String fechaTrabajo;

  const SerieEncontrada({
    required this.serie,
    required this.tipoEquipo,
    required this.descripcion,
    required this.ordenTrabajo,
    required this.rutTecnico,
    required this.fechaTrabajo,
  });
}

/// Orquesta el flujo de consumo de materiales TRAZA:
/// stock desde la API traza (vía proxy), OTs pendientes desde `produccion`,
/// y registro del consumo en la tabla `consumos_traza` de Supabase.
class TrazaConsumoService {
  final _proxy = TrazaProxyService();
  SupabaseClient get _db => Supabase.instance.client;

  // ── Categorización (validada contra el inventario real 2026-08-24) ────────

  /// Familias de la API traza que entran a la pantalla de consumo.
  static const _familiasConsumo = {
    'INSTALACIONES DOMICILIARIAS',
    'CONSTRUCCION FIBRA OPTICA',
    'CONSTRUCCION PLANTA INTERNA',
    'CONSTRUCCION PLANTA EXTERNA',
  };

  /// Nombre ERP (SAP) → categoría canónica. Retorna null si el material no
  /// es consumible por orden (queda oculto).
  ///
  /// Base: LogisticaService.categorizar (agente_desconexiones / KRP; ambos
  /// catálogos vienen de SAP) + reglas extra para variantes de traza.
  static String? categorizar(String nombreErp) {
    final n = nombreErp.toUpperCase();

    // ── Variantes específicas del catálogo traza ──
    // "ET TOP BOX": así viene de SAP (SET TOP BOX con la S cortada).
    if (n.contains('TOP BOX')) return 'Decodificador';
    if (n.contains('CONECTOR') && n.contains('RAPIDO')) {
      return 'Conector de campo';
    }
    if (n.contains('PASAMURO') && n.contains('BLANCO')) {
      return 'Pasacable blanco';
    }
    if (n.contains('PASAMURO')) return 'Pasacable negro';
    if (n.contains('SOPORTE TIPO S')) return 'Soportes drop';
    if (n.contains('GANCHO') && n.contains('RETENCION')) return 'Soportes drop';
    if (n.contains('ABRAZADERA') && n.contains('GALAXI')) {
      return 'Soportes drop';
    }
    // Drops "OPTITAP" que no traen la palabra DROP en el nombre.
    if (n.contains('OPTITAP')) {
      final drop = _dropPorLargo(n);
      if (drop != null) return drop;
    }

    // ── Reglas base (mismas de KRP/agente) ──
    if (n.contains('ROSETA')) return 'Roseta';
    if (n.contains('JUMPER') || n.contains('LATIGUILLO')) return 'Jumper';
    if (n.contains('AMARRA')) return 'Amarras plásticas';
    if (n.contains('FICHA') &&
        (n.contains('ABONADO') || n.contains('CLIENTE'))) {
      return 'Ficha de abonado';
    }
    if ((n.contains('SOPORTE') &&
            (n.contains('DROP') || n.contains('CABLE'))) ||
        (n.contains('ABRAZADERA') && n.contains('DROP'))) {
      return 'Soportes drop';
    }
    if (n.contains('CONECTOR') &&
        (n.contains('CAMPO') ||
            n.contains('SCAPC') ||
            n.contains('SC/APC') ||
            n.contains('SC-APC') ||
            n.contains('SC/UPC') ||
            n.contains('SC APC'))) {
      return 'Conector de campo';
    }

    if (n.contains('DROP') ||
        n.contains('HIBRIDO') ||
        n.contains('FSTCONN') ||
        (n.contains('FO') && n.contains('MTS'))) {
      final drop = _dropPorLargo(n);
      if (drop != null) return drop;
    }

    if (n.contains('EXTENSOR') || n.contains('K562') || n.contains('H3601')) {
      return 'Extensor';
    }

    if (n.contains(' ONT') ||
        n.startsWith('ONT') ||
        n.contains(' ONU') ||
        n.startsWith('ONU')) {
      if (n.contains('HUAWEI')) return 'ONT Huawei';
      return 'ONT ZTE';
    }

    if (n.contains('DECODIFICADOR') ||
        n.contains('DECO ') ||
        n.contains('STB ') ||
        n.contains('SET TOP') ||
        n.contains('CPE ') ||
        n.contains('FUSE4K') ||
        n.contains('FUSE 4K')) {
      return 'Decodificador';
    }

    if (n.contains('CANCAMO') || n.contains('CÁNCAMO')) return 'Cáncamos';
    if (n.contains('GRAMPA') && n.contains('NEGRA')) return 'Grampa negra';
    if (n.contains('GRAMPA') && (n.contains('BLANCA') || n.contains('CHS'))) {
      return 'Grampa blanca';
    }
    if (n.contains('PASACABLE') && n.contains('BLANCO')) {
      return 'Pasacable blanco';
    }
    if (n.contains('PASACABLE') && n.contains('NEGRO')) {
      return 'Pasacable negro';
    }
    if (n.contains('CABLE UTP') || n.contains('CAT5E')) return 'Cable UTP';
    if (n.contains('RJ45') || n.contains('RJ 45') || n.contains('RJ-45')) {
      return 'Conector RJ45';
    }
    if (n.contains('MICRO USB')) return 'Micro USB';
    if (n.contains('HDMI')) return 'Cable HDMI';

    // ── HFC (los técnicos TRAZA sí hacen coaxial) ──
    // Nota: "CABLE COAXIAL ... RG-6" no debe caer en conector F.
    if (n.contains('CABLE COAXIAL') ||
        (n.contains('COAXIAL') && n.contains('RG'))) {
      return 'Cable coaxial';
    }
    if (n.contains('CONECTOR') &&
        (n.contains('RG6') || n.contains('RG-6') || n.contains(' F RG'))) {
      return 'Conector F RG-6';
    }
    if (n.contains('CONECTOR') &&
        n.contains('PPC') &&
        n.contains('LOCKING')) {
      return 'Conector F RG-6';
    }

    return null;
  }

  static String? _dropPorLargo(String n) {
    if (n.contains('300')) return 'Drop 300m';
    if (n.contains('220') || n.contains('200')) return 'Drop 200m';
    if (n.contains('150')) return 'Drop 150m';
    if (n.contains('100')) return 'Drop 100m';
    return null;
  }

  // ── Stock ─────────────────────────────────────────────────────────────────

  /// Trae el inventario del técnico desde la API traza y lo agrupa por
  /// categorías de consumo.
  Future<StockConsumoTecnico> obtenerStock(String rut) async {
    final inventario = await _proxy.obtenerInventarioPorRut(rut);

    final items = <ItemStockConsumo>[];
    final porCategoria = <String, int>{};
    final sinCategoria = <InventarioMaterial>[];

    for (final mat in inventario) {
      if (!mat.tieneStock) continue;
      if (!_familiasConsumo.contains(mat.nombreFamilia)) continue;

      final cat = categorizar(mat.nombreMaterial);
      if (cat == null) {
        sinCategoria.add(mat);
        continue;
      }

      // El tratamiento lo decide la CATEGORÍA (consumo_reglas), no el flag
      // del inventario: p.ej. la ONT viene seriada de traza pero en TRAZA
      // se declara por cantidad como material.
      if (categoriaEsSeriada(cat) && mat.esSeriado) {
        // Un ítem por serie, para seleccionarlas una a una.
        // OJO backend traza: series[] puede traer series históricas de más
        // (ej. 1094 series con stock 275) — el saldo confiable es
        // cantidadEnInventario; las series sirven para elegir la física.
        for (final serie in mat.series) {
          items.add(ItemStockConsumo(
            materialId: mat.materialId,
            nombre: mat.nombreMaterial,
            sku: mat.skuMaterial,
            categoria: cat,
            esSeriado: true,
            cantidad: 1,
            serie: serie,
          ));
        }
      } else {
        items.add(ItemStockConsumo(
          materialId: mat.materialId,
          nombre: mat.nombreMaterial,
          sku: mat.skuMaterial,
          categoria: cat,
          esSeriado: false,
          cantidad: mat.cantidadEnInventario.toInt(),
        ));
      }
      porCategoria[cat] =
          (porCategoria[cat] ?? 0) + mat.cantidadEnInventario.toInt();
    }

    if (sinCategoria.isNotEmpty) {
      debugPrint(
        '[TrazaConsumo] ${sinCategoria.length} ítems con stock sin categoría '
        '(ocultos): ${sinCategoria.take(10).map((m) => m.nombreMaterial).join(" | ")}',
      );
    }

    return StockConsumoTecnico(
      rut: rut,
      items: items,
      porCategoria: porCategoria,
      sinCategoria: sinCategoria,
    );
  }

  // ── OTs pendientes de consumo ─────────────────────────────────────────────

  /// Órdenes completadas del técnico en el mes [mes]/[anno] que aún no
  /// tienen consumo declarado en `consumos_traza`.
  Future<List<OrdenPendienteConsumo>> obtenerOrdenesPendientesMes(
    String rut, {
    required int mes,
    required int anno,
  }) async {
    final inicio = DateTime(anno, mes, 1);
    final fin = DateTime(anno, mes + 1, 1);
    String fecha(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final rows = await _db
        .from('produccion')
        .select(
            'orden_trabajo, tipo_orden, tipo_actividad, fecha_trabajo, cliente, direccion, zona_trabajo')
        .eq('rut_tecnico', rut)
        .eq('estado', 'Completado')
        .gte('fecha_trabajo', fecha(inicio))
        .lt('fecha_trabajo', fecha(fin))
        .order('fecha_trabajo', ascending: false);

    // Declaraciones existentes. El ERP es la fuente de verdad: la OT deja de
    // estar pendiente SOLO cuando el traspaso está confirmado (ok/parcial).
    // Con declaración pero traspaso pendiente/error → sigue en la lista,
    // marcada para REENVIAR (sin re-seleccionar materiales).
    final consumidas = await _db
        .from('consumos_traza')
        .select('orden_trabajo, traspaso_estado')
        .eq('rut_tecnico', rut);
    final yaDeclaradas = <String>{};
    final porReenviar = <String>{};
    for (final r in consumidas as List) {
      final ot = r['orden_trabajo'] as String? ?? '';
      if (ot.isEmpty) continue;
      final estado = r['traspaso_estado'] as String? ?? 'pendiente';
      if (estado == 'ok' || estado == 'parcial' || estado == 'sin_consumo') {
        yaDeclaradas.add(ot);
      } else {
        porReenviar.add(ot);
      }
    }

    // Dedup por orden_trabajo (produccion puede traer más de una fila por OT)
    final vistas = <String>{};
    final pendientes = <OrdenPendienteConsumo>[];
    for (final r in rows as List) {
      final ot = r['orden_trabajo'] as String? ?? '';
      if (ot.isEmpty || vistas.contains(ot) || yaDeclaradas.contains(ot)) {
        continue;
      }
      vistas.add(ot);

      // Preferir la tipificación MÁS específica entre tipo_orden y
      // tipo_actividad: "Alta 2 Play" gana sobre "Alta", pero
      // "Modificación de Servicio" gana sobre "Modificación".
      String limpio(dynamic v) {
        final s = (v as String? ?? '').trim();
        return (s == 'Sin Datos' || s == 'NaN') ? '' : s;
      }

      final tipoOrden = limpio(r['tipo_orden']);
      final tipoAct = limpio(r['tipo_actividad']);
      final tipo = tipoOrden.length >= tipoAct.length ? tipoOrden : tipoAct;

      pendientes.add(OrdenPendienteConsumo(
        ordenTrabajo: ot,
        tipoActividad: tipo,
        fechaTrabajo: r['fecha_trabajo']?.toString() ?? '',
        cliente: r['cliente'] as String? ?? '',
        direccion: r['direccion'] as String? ?? '',
        comuna: r['zona_trabajo'] as String? ?? '',
        traspasoPendiente: porReenviar.contains(ot),
      ));
    }
    return pendientes;
  }

  /// Cantidad de OTs pendientes de consumo del mes (para la card de Tu Mes).
  Future<int> contarPendientesMes({
    required String rut,
    required int mes,
    required int anno,
  }) async {
    final pendientes =
        await obtenerOrdenesPendientesMes(rut, mes: mes, anno: anno);
    return pendientes.length;
  }

  // ── Registro del consumo ──────────────────────────────────────────────────

  /// Registra el consumo: guarda la declaración en `consumos_traza`
  /// (respaldo interno + candado anti doble descuento) y luego postea el
  /// traspaso al ERP traza materiales, que es LA FUENTE DE VERDAD.
  ///
  /// Si el ERP no confirma (red caída / rechazo), la declaración queda con
  /// traspaso_estado 'pendiente'/'error' y la OT SIGUE PENDIENTE en el front
  /// hasta que un reenvío logre la confirmación.
  Future<ConsumoResult> registrarConsumo({
    required String ordenTrabajo,
    required String rutTecnico,
    required String tipoActividad,
    required String fechaTrabajo,
    required String direccion,
    required List<ItemStockConsumo> noSeriados,
    required Map<ItemStockConsumo, int> cantidades,
    required List<EquipoInstaladoToa> equiposToa,
    Map<String, String> skuPorSerie = const {},
  }) async {
    final noSeriadosJson = <Map<String, dynamic>>[];
    for (final item in noSeriados) {
      final cant = cantidades[item] ?? 0;
      if (cant <= 0) continue;
      noSeriadosJson.add({
        'material_id': item.materialId,
        'sku': item.sku,
        'nombre': item.nombre,
        'categoria': item.categoria,
        'cantidad': cant,
      });
    }

    // Los seriados NO los digita el técnico: vienen de lo registrado en TOA.
    // El sku se resuelve desde el inventario actual (necesario para el ERP).
    final seriadosJson = equiposToa
        .map((e) => {
              'nombre': e.descripcion,
              'categoria': e.categoria,
              'serie': e.serie,
              'sku': skuPorSerie[e.serie],
              'fuente': 'toa',
            })
        .toList();

    // 1. Guardar la declaración (candado: única por OT+técnico)
    try {
      await _db.from('consumos_traza').insert({
        'orden_trabajo': ordenTrabajo.trim(),
        'rut_tecnico': rutTecnico,
        'tipo_actividad': tipoActividad,
        'fecha_trabajo': fechaTrabajo.isNotEmpty ? fechaTrabajo : null,
        'direccion': direccion,
        'no_seriados': noSeriadosJson,
        'seriados': seriadosJson,
        'total_items': noSeriadosJson.length + seriadosJson.length,
        'traspaso_estado': 'pendiente',
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        return const ConsumoResult(
          exito: false,
          mensaje: 'Esta orden ya tiene un consumo declarado.',
        );
      }
      return ConsumoResult(exito: false, mensaje: e.message);
    } catch (e) {
      return ConsumoResult(exito: false, mensaje: e.toString());
    }

    // 2. Postear el traspaso al ERP (descuento real de bodega)
    final estado = await _enviarTraspasoErp(
      ordenTrabajo: ordenTrabajo.trim(),
      rutTecnico: rutTecnico,
      fechaTrabajo: fechaTrabajo,
      direccion: direccion,
      noSeriados: noSeriadosJson,
      seriados: seriadosJson,
    );

    return ConsumoResult(
      exito: true,
      mensaje: 'Consumo registrado',
      traspasoEstado: estado,
    );
  }

  /// Reintenta el traspaso al ERP de una declaración guardada (OT que quedó
  /// "por reenviar"). No re-selecciona materiales: usa lo ya declarado.
  Future<ConsumoResult> reenviarTraspaso({
    required String ordenTrabajo,
    required String rutTecnico,
  }) async {
    final rows = await _db
        .from('consumos_traza')
        .select('no_seriados, seriados, fecha_trabajo, direccion, traspaso_estado')
        .eq('orden_trabajo', ordenTrabajo)
        .eq('rut_tecnico', rutTecnico)
        .limit(1);
    if ((rows as List).isEmpty) {
      return const ConsumoResult(
          exito: false, mensaje: 'No hay declaración guardada para esta orden.');
    }
    final row = Map<String, dynamic>.from(rows.first);
    if (row['traspaso_estado'] == 'ok' || row['traspaso_estado'] == 'parcial') {
      return const ConsumoResult(
          exito: true,
          mensaje: 'El consumo ya estaba confirmado en bodega.',
          traspasoEstado: 'ok');
    }

    List<Map<String, dynamic>> lista(dynamic v) => (v as List? ?? [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final noSeriados = lista(row['no_seriados']);
    final seriados = lista(row['seriados']);

    // Resolver SKUs de series que quedaron sin sku (declaraciones antiguas)
    if (seriados.any((s) => (s['sku'] ?? '') == '' || s['sku'] == null)) {
      try {
        final stock = await obtenerStock(rutTecnico);
        final mapa = <String, String>{
          for (final i in stock.items)
            if (i.esSeriado && i.serie != null) i.serie!: i.sku,
        };
        for (final s in seriados) {
          if ((s['sku'] ?? '') == '' || s['sku'] == null) {
            s['sku'] = mapa[s['serie']?.toString()];
          }
        }
      } catch (_) {}
    }

    final estado = await _enviarTraspasoErp(
      ordenTrabajo: ordenTrabajo,
      rutTecnico: rutTecnico,
      fechaTrabajo: row['fecha_trabajo']?.toString() ?? '',
      direccion: row['direccion']?.toString() ?? '',
      noSeriados: noSeriados,
      seriados: seriados,
    );

    final ok = estado == 'ok' || estado == 'parcial';
    return ConsumoResult(
      exito: ok,
      mensaje: ok
          ? 'Consumo confirmado en bodega'
          : 'Bodega aún no confirma el consumo',
      traspasoEstado: estado,
    );
  }

  /// Postea el traspaso al ERP y anota el resultado en la fila de
  /// consumos_traza. Devuelve el estado: ok | parcial | error | pendiente.
  Future<String> _enviarTraspasoErp({
    required String ordenTrabajo,
    required String rutTecnico,
    required String fechaTrabajo,
    required String direccion,
    required List<Map<String, dynamic>> noSeriados,
    required List<Map<String, dynamic>> seriados,
  }) async {
    // Armar líneas: codigoMaterial = skuMaterial del inventario (así lo
    // busca material_logistica, verificado 2026-08-26).
    final lineas = <Map<String, dynamic>>[];
    final erroresLocales = <Map<String, dynamic>>[];
    for (final m in noSeriados) {
      final sku = m['sku']?.toString() ?? '';
      if (sku.isEmpty) continue;
      lineas.add({'codigoMaterial': sku, 'cantidad': m['cantidad'] ?? 0});
    }
    for (final s in seriados) {
      final sku = s['sku']?.toString() ?? '';
      if (sku.isEmpty) {
        erroresLocales.add({
          'serie': s['serie'],
          'motivo': 'Serie sin SKU en el inventario actual del técnico',
          // No hay SKU (ese es justo el problema) — se informa el
          // material según la sábana TOA para que bodega sepa qué cargar.
          'categoria': s['categoria'],
          'material_toa': s['nombre'],
        });
        continue;
      }
      lineas.add({
        'codigoMaterial': sku,
        'cantidad': 1,
        'serie': s['serie'],
      });
    }

    String hoyIso() {
      final n = DateTime.now();
      return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    }

    // Declaración CERO (reparación sin materiales): no hay nada que
    // descontar en bodega → no se postea al ERP y queda confirmada.
    if (lineas.isEmpty && erroresLocales.isEmpty) {
      try {
        await _db.from('consumos_traza').update({
          'traspaso_estado': 'sin_consumo',
          'traspaso_at': DateTime.now().toIso8601String(),
        }).eq('orden_trabajo', ordenTrabajo).eq('rut_tecnico', rutTecnico);
      } catch (_) {}
      return 'sin_consumo';
    }

    String estado;
    Map<String, dynamic> anotacion = {};
    try {
      final resp = await _proxy.post('/traspasos/tecnico', {
        'numeroOt': ordenTrabajo,
        'direccion': direccion.isNotEmpty ? direccion : 'Sin dirección',
        'rutTecnico': rutTecnico,
        'fecha': fechaTrabajo.isNotEmpty ? fechaTrabajo : hoyIso(),
        'lineas': lineas,
      });

      final elementos = (resp['elementosCreadosIds'] as List?) ?? [];
      final errores = [
        ...((resp['errores'] as List?) ?? []),
        ...erroresLocales,
      ];
      if (elementos.isNotEmpty && errores.isEmpty) {
        estado = 'ok';
      } else if (elementos.isNotEmpty) {
        estado = 'parcial';
      } else {
        estado = 'error';
      }
      anotacion = {
        'traspaso_estado': estado,
        'traspaso_id': resp['traspasoId'],
        'ot_erp_id': resp['otId'],
        'traspaso_errores': errores,
        'traspaso_at': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      debugPrint('[Traspaso] ERP no contactado: $e');
      estado = 'pendiente';
      anotacion = {
        'traspaso_estado': 'pendiente',
        'traspaso_errores': [
          {'motivo': 'ERP no contactado: $e'}
        ],
      };
    }

    try {
      await _db
          .from('consumos_traza')
          .update(anotacion)
          .eq('orden_trabajo', ordenTrabajo)
          .eq('rut_tecnico', rutTecnico);
    } catch (e) {
      debugPrint('[Traspaso] no se pudo anotar resultado: $e');
    }

    // Aviso por correo a bodega/supervisión cuando el ERP rechaza (total o
    // parcialmente) la declaración — típicamente series instaladas que no
    // están cargadas en la bodega del técnico. No bloquea el flujo.
    if (estado == 'error' || estado == 'parcial') {
      unawaited(_avisarErrorConsumoPorCorreo(
        ordenTrabajo: ordenTrabajo,
        rutTecnico: rutTecnico,
        estado: estado,
        anotacion: anotacion,
      ));
    }
    return estado;
  }

  Future<void> _avisarErrorConsumoPorCorreo({
    required String ordenTrabajo,
    required String rutTecnico,
    required String estado,
    required Map<String, dynamic> anotacion,
  }) async {
    try {
      await _db.functions.invoke('email-error-consumo', body: {
        'orden_trabajo': ordenTrabajo,
        'rut_tecnico': rutTecnico,
        'traspaso_estado': estado,
        'traspaso_errores': anotacion['traspaso_errores'],
        'traspaso_id': anotacion['traspaso_id'],
        'ot_erp_id': anotacion['ot_erp_id'],
      }).timeout(const Duration(seconds: 15));
      debugPrint('✅ [Correo] aviso de consumo $estado enviado ($ordenTrabajo)');
    } catch (e) {
      debugPrint('⚠️ [Correo] aviso de consumo $estado falló: $e');
    }
  }

  // ── Historial de consumos declarados ──────────────────────────────────────

  /// Órdenes con consumo declarado en el mes (por fecha de ejecución de la OT),
  /// más recientes primero.
  Future<List<ConsumoDeclarado>> obtenerConsumosMes(
    String rut, {
    required int mes,
    required int anno,
  }) async {
    final inicio = DateTime(anno, mes, 1);
    final fin = DateTime(anno, mes + 1, 1);
    String fecha(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final rows = await _db
        .from('consumos_traza')
        .select(
            'orden_trabajo, tipo_actividad, fecha_trabajo, created_at, no_seriados, seriados')
        .eq('rut_tecnico', rut)
        .gte('fecha_trabajo', fecha(inicio))
        .lt('fecha_trabajo', fecha(fin))
        .order('fecha_trabajo', ascending: false)
        .order('created_at', ascending: false);

    return (rows as List).map((r) {
      List<Map<String, dynamic>> lista(dynamic v) => (v as List? ?? [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

      return ConsumoDeclarado(
        ordenTrabajo: r['orden_trabajo'] as String? ?? '',
        tipoActividad: r['tipo_actividad'] as String? ?? '',
        fechaTrabajo: r['fecha_trabajo']?.toString() ?? '',
        fechaConsumo: DateTime.tryParse(r['created_at']?.toString() ?? '')
                ?.toLocal() ??
            DateTime.now(),
        noSeriados: lista(r['no_seriados']),
        seriados: lista(r['seriados']),
      );
    }).toList();
  }

  /// Desglose de consumos declarados de los últimos [meses] meses
  /// (por fecha de ejecución de la OT), del más reciente al más antiguo.
  /// Incluye meses sin consumos (con ceros).
  Future<List<ResumenMesConsumo>> resumenConsumosUltimosMeses(
    String rut, {
    int meses = 6,
  }) async {
    final ahora = DateTime.now();
    final inicio = DateTime(ahora.year, ahora.month - (meses - 1), 1);
    final inicioStr =
        '${inicio.year}-${inicio.month.toString().padLeft(2, '0')}-01';

    final rows = await _db
        .from('consumos_traza')
        .select('fecha_trabajo, total_items')
        .eq('rut_tecnico', rut)
        .gte('fecha_trabajo', inicioStr);

    // Acumular por año-mes
    final ordenesPorMes = <String, int>{};
    final materialesPorMes = <String, int>{};
    for (final r in rows as List) {
      final f = DateTime.tryParse(r['fecha_trabajo']?.toString() ?? '');
      if (f == null) continue;
      final key = '${f.year}-${f.month}';
      ordenesPorMes[key] = (ordenesPorMes[key] ?? 0) + 1;
      materialesPorMes[key] = (materialesPorMes[key] ?? 0) +
          (r['total_items'] as num? ?? 0).toInt();
    }

    // Generar los N meses, del actual hacia atrás
    final resumen = <ResumenMesConsumo>[];
    for (var i = 0; i < meses; i++) {
      final d = DateTime(ahora.year, ahora.month - i, 1);
      final key = '${d.year}-${d.month}';
      resumen.add(ResumenMesConsumo(
        mes: d.month,
        anno: d.year,
        ordenes: ordenesPorMes[key] ?? 0,
        materiales: materialesPorMes[key] ?? 0,
      ));
    }
    return resumen;
  }

  // ── Buscador de series (todos los meses) ──────────────────────────────────

  /// Busca una serie en el histórico completo `equipos_seriados_traza`,
  /// opcionalmente filtrando por tipo (ONT / DECO / EXTENSOR).
  /// La búsqueda es parcial: basta con parte de la serie.
  Future<List<SerieEncontrada>> buscarSeries({
    required String texto,
    String? tipoEquipo,
    int limite = 50,
  }) async {
    var query = _db
        .from('equipos_seriados_traza')
        .select(
            'serie, tipo_equipo, descripcion, orden_trabajo, rut_tecnico, fecha_trabajo')
        .ilike('serie', '%${texto.trim()}%');

    if (tipoEquipo != null && tipoEquipo.isNotEmpty) {
      query = query.eq('tipo_equipo', tipoEquipo);
    }

    final rows =
        await query.order('fecha_trabajo', ascending: false).limit(limite);

    return (rows as List)
        .map((r) => SerieEncontrada(
              serie: r['serie'] as String? ?? '',
              tipoEquipo: r['tipo_equipo'] as String? ?? 'OTRO',
              descripcion: r['descripcion'] as String? ?? '',
              ordenTrabajo: r['orden_trabajo'] as String? ?? '',
              rutTecnico: r['rut_tecnico'] as String? ?? '',
              fechaTrabajo: r['fecha_trabajo']?.toString() ?? '',
            ))
        .toList();
  }

  // ── Estadísticas para Tu Mes ──────────────────────────────────────────────

  /// Resumen del mes para la card de Tu Mes: total de órdenes con consumo
  /// declarado y total de materiales, calculado desde nuestros registros.
  Future<Map<String, dynamic>> estadisticasMes({
    required String rut,
    required int mes,
    required int anno,
  }) async {
    final inicio = DateTime(anno, mes, 1);
    final fin = DateTime(anno, mes + 1, 1);

    final rows = await _db
        .from('consumos_traza')
        .select('orden_trabajo, total_items, created_at')
        .eq('rut_tecnico', rut)
        .gte('created_at', inicio.toIso8601String())
        .lt('created_at', fin.toIso8601String());

    final lista = rows as List;
    var totalMateriales = 0;
    for (final r in lista) {
      totalMateriales += (r['total_items'] as num? ?? 0).toInt();
    }

    return {
      'ordenes': lista.length,
      'materiales': totalMateriales,
    };
  }
}
