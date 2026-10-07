/// Reglas MIN/MAX de consumo por categoría y tipo de actividad.
///
/// Fuente: Excel `recetas_2026_08_25_10_35_26.xlsx` (aplicado tal cual).
/// 3 recetas, vinculadas por tipo de actividad:
/// - "Recetas ALTAS y MIGRACIONES"  → Alta; Migración (con mínimos).
/// - "Recetas exclusiva Traslados"  → Alta Traslado (con mínimos).
/// - "Receta General Reparaciones-Modificaciones-upgrade-downgrade"
///   → Modificación*, Reparación, Upgrade/Downgrade promoción (solo máximos);
///   además es el fallback para actividades no reconocidas.
///
/// Notas:
/// - "CABLES DROP" del Excel = nuestras 4 categorías Drop; el mín/máx es del
///   GRUPO completo (1 drop en total, obligatorio en altas y traslados).
/// - ONT / IPTV (decos) / Extensores del Excel no se validan aquí: los
///   equipos seriados vienen SOLO LECTURA desde TOA (equipos_seriados_traza).
/// - Cable coaxial y Conector F RG-6 (HFC) no vienen en el Excel: quedan
///   visibles sin tope hasta que bodega los agregue a la receta.
library;

class ConsumoRegla {
  final String categoria;
  final int? minimo;
  final int? maximo;

  const ConsumoRegla({
    required this.categoria,
    this.minimo,
    this.maximo,
  });
}

enum TipoReceta { altasMigracion, traslados, reparacionesModificaciones }

// ── Categorías canónicas (lo único que ve el técnico) ────────────────────────

class CategoriaMaterial {
  final String nombre;
  final bool esSeriado;

  const CategoriaMaterial(this.nombre, {this.esSeriado = false});
}

/// Catálogo de categorías de consumo TRAZA.
/// PENDIENTE bodega: Gateway WiFi Sercomm/ZTE quedó fuera a propósito
/// hasta confirmar si se consume por orden.
const kCategoriasConsumo = <CategoriaMaterial>[
  // No seriados — fibra
  CategoriaMaterial('Drop 100m'),
  CategoriaMaterial('Drop 150m'),
  CategoriaMaterial('Drop 200m'),
  CategoriaMaterial('Drop 300m'),
  CategoriaMaterial('Roseta'),
  CategoriaMaterial('Jumper'),
  CategoriaMaterial('Conector de campo'),
  CategoriaMaterial('Ficha de abonado'),
  CategoriaMaterial('Soportes drop'),
  CategoriaMaterial('Cáncamos'),
  CategoriaMaterial('Amarras plásticas'),
  CategoriaMaterial('Grampa negra'),
  CategoriaMaterial('Grampa blanca'),
  CategoriaMaterial('Pasacable negro'),
  CategoriaMaterial('Pasacable blanco'),
  CategoriaMaterial('Cable UTP'),
  CategoriaMaterial('Conector RJ45'),
  CategoriaMaterial('Micro USB'),
  CategoriaMaterial('Cable HDMI'),
  // No seriados — HFC (sin tope en receta actual)
  CategoriaMaterial('Cable coaxial'),
  CategoriaMaterial('Conector F RG-6'),
  // Seriados: las series NO las elige el técnico — vienen pre-cargadas
  // (solo lectura) desde lo registrado en TOA (equipos_seriados_traza).
  CategoriaMaterial('ONT ZTE', esSeriado: true),
  CategoriaMaterial('ONT Huawei', esSeriado: true),
  CategoriaMaterial('Decodificador', esSeriado: true),
  CategoriaMaterial('Extensor', esSeriado: true),
];

/// Tratamiento de la categoría en la pantalla (material vs por serie).
/// Manda por sobre el flag esSeriado del inventario traza.
bool categoriaEsSeriada(String categoria) {
  for (final c in kCategoriasConsumo) {
    if (c.nombre == categoria) return c.esSeriado;
  }
  return false;
}

// ── Grupo drop ───────────────────────────────────────────────────────────────

const kConsumoCategoriasDrop = [
  'Drop 100m',
  'Drop 150m',
  'Drop 200m',
  'Drop 300m',
];

/// Máximo de drops en total por orden (Excel: CABLES DROP máx 1).
const kConsumoMaxDropTotal = 1;

/// Mínimo de drops según receta (Excel: 1 en altas/traslados, 0 en repar.).
int consumoMinDropTotal(String tipoActividad) =>
    tipoRecetaPara(tipoActividad) == TipoReceta.reparacionesModificaciones
        ? 0
        : 1;

// ── Reglas por tipo de receta (valores del Excel) ────────────────────────────

// "Recetas ALTAS y MIGRACIONES" (Alta; Migración)
const _reglasAltasMigracion = [
  ConsumoRegla(categoria: 'Drop 100m', maximo: 1), // grupo: mín 1, máx 1 total
  ConsumoRegla(categoria: 'Drop 150m', maximo: 1),
  ConsumoRegla(categoria: 'Drop 200m', maximo: 1),
  ConsumoRegla(categoria: 'Drop 300m', maximo: 1),
  ConsumoRegla(categoria: 'Ficha de abonado', minimo: 1, maximo: 1),
  ConsumoRegla(categoria: 'Soportes drop', maximo: 15),
  ConsumoRegla(categoria: 'Cáncamos', maximo: 2),
  ConsumoRegla(categoria: 'Amarras plásticas', minimo: 5, maximo: 10),
  ConsumoRegla(categoria: 'Roseta', minimo: 1, maximo: 1),
  ConsumoRegla(categoria: 'Jumper', minimo: 1, maximo: 1),
  ConsumoRegla(categoria: 'Conector de campo', minimo: 1, maximo: 2),
  ConsumoRegla(categoria: 'Micro USB', maximo: 1),
  ConsumoRegla(categoria: 'Pasacable negro', maximo: 2),
  ConsumoRegla(categoria: 'Pasacable blanco', maximo: 2),
  ConsumoRegla(categoria: 'Cable UTP', maximo: 15),
  ConsumoRegla(categoria: 'Conector RJ45', maximo: 2),
  ConsumoRegla(categoria: 'Grampa negra', maximo: 10),
  ConsumoRegla(categoria: 'Grampa blanca', maximo: 10),
  ConsumoRegla(categoria: 'Cable HDMI', maximo: 3),
];

// "Recetas exclusiva Traslados" (Alta Traslado) — mismos materiales que altas
const _reglasTraslados = [
  ConsumoRegla(categoria: 'Drop 100m', maximo: 1),
  ConsumoRegla(categoria: 'Drop 150m', maximo: 1),
  ConsumoRegla(categoria: 'Drop 200m', maximo: 1),
  ConsumoRegla(categoria: 'Drop 300m', maximo: 1),
  ConsumoRegla(categoria: 'Ficha de abonado', minimo: 1, maximo: 1),
  ConsumoRegla(categoria: 'Soportes drop', maximo: 15),
  ConsumoRegla(categoria: 'Cáncamos', maximo: 2),
  ConsumoRegla(categoria: 'Amarras plásticas', minimo: 5, maximo: 10),
  ConsumoRegla(categoria: 'Roseta', minimo: 1, maximo: 1),
  ConsumoRegla(categoria: 'Jumper', minimo: 1, maximo: 1),
  ConsumoRegla(categoria: 'Conector de campo', minimo: 1, maximo: 2),
  ConsumoRegla(categoria: 'Micro USB', maximo: 1),
  ConsumoRegla(categoria: 'Pasacable negro', maximo: 2),
  ConsumoRegla(categoria: 'Pasacable blanco', maximo: 2),
  ConsumoRegla(categoria: 'Cable UTP', maximo: 15),
  ConsumoRegla(categoria: 'Conector RJ45', maximo: 2),
  ConsumoRegla(categoria: 'Grampa negra', maximo: 10),
  ConsumoRegla(categoria: 'Grampa blanca', maximo: 10),
  ConsumoRegla(categoria: 'Cable HDMI', maximo: 3),
];

// "Receta General Reparaciones-Modificaciones-upgrade-downgrade"
const _reglasReparacionesModificaciones = [
  ConsumoRegla(categoria: 'Drop 100m', maximo: 1),
  ConsumoRegla(categoria: 'Drop 150m', maximo: 1),
  ConsumoRegla(categoria: 'Drop 200m', maximo: 1),
  ConsumoRegla(categoria: 'Drop 300m', maximo: 1),
  ConsumoRegla(categoria: 'Ficha de abonado', maximo: 1),
  ConsumoRegla(categoria: 'Soportes drop', maximo: 15),
  ConsumoRegla(categoria: 'Cáncamos', maximo: 2),
  ConsumoRegla(categoria: 'Amarras plásticas', maximo: 10),
  ConsumoRegla(categoria: 'Roseta', maximo: 1),
  ConsumoRegla(categoria: 'Jumper', maximo: 1),
  ConsumoRegla(categoria: 'Conector de campo', maximo: 2),
  ConsumoRegla(categoria: 'Micro USB', maximo: 1),
  ConsumoRegla(categoria: 'Pasacable negro', maximo: 2),
  ConsumoRegla(categoria: 'Pasacable blanco', maximo: 2),
  ConsumoRegla(categoria: 'Cable UTP', maximo: 15),
  ConsumoRegla(categoria: 'Conector RJ45', maximo: 2),
  ConsumoRegla(categoria: 'Grampa negra', maximo: 10),
  ConsumoRegla(categoria: 'Grampa blanca', maximo: 10),
  ConsumoRegla(categoria: 'Cable HDMI', maximo: 3),
];

// ── Matcheo tipo de actividad → receta (vínculos del Excel) ──────────────────

TipoReceta tipoRecetaPara(String tipoActividad) {
  final t = tipoActividad.toLowerCase();

  // "Alta Traslado" debe evaluarse antes que "Alta"
  if (t.contains('traslado')) return TipoReceta.traslados;
  if (t.contains('alta') || t.contains('migra') || t.contains('instalaci')) {
    return TipoReceta.altasMigracion;
  }
  // Modificación*, Reparación, Upgrade/Downgrade promoción + fallback
  return TipoReceta.reparacionesModificaciones;
}

List<ConsumoRegla> _reglasPara(TipoReceta tipo) {
  switch (tipo) {
    case TipoReceta.altasMigracion:
      return _reglasAltasMigracion;
    case TipoReceta.traslados:
      return _reglasTraslados;
    case TipoReceta.reparacionesModificaciones:
      return _reglasReparacionesModificaciones;
  }
}

ConsumoRegla? consumoReglaPara(String categoria, String tipoActividad) {
  for (final r in _reglasPara(tipoRecetaPara(tipoActividad))) {
    if (r.categoria == categoria) return r;
  }
  return null;
}

int? consumoMinimo(String categoria, String tipoActividad) =>
    consumoReglaPara(categoria, tipoActividad)?.minimo;

int? consumoMaximo(String categoria, String tipoActividad) =>
    consumoReglaPara(categoria, tipoActividad)?.maximo;

/// Altas/Migración y Traslados exigen mínimos obligatorios.
bool consumoExigirMinimos(String tipoActividad) =>
    tipoRecetaPara(tipoActividad) != TipoReceta.reparacionesModificaciones;

// ── Mínimos de equipos seriados (se corroboran contra TOA) ───────────────────

/// Mínimos de equipos según la receta del Excel. El técnico NO los edita:
/// se corroboran contra lo cargado desde `equipos_seriados_traza`.
/// Clave = tipo_equipo de la tabla (ONT / DECO / EXTENSOR).
Map<String, int> consumoMinimosEquipos(String tipoActividad) {
  switch (tipoRecetaPara(tipoActividad)) {
    case TipoReceta.altasMigracion:
      return const {'ONT': 1}; // Excel: ALTAS y MIGRACIONES → ONT mín 1
    case TipoReceta.traslados:
    case TipoReceta.reparacionesModificaciones:
      return const {};
  }
}

/// Nombre legible del tipo de equipo para los mensajes.
const kNombreTipoEquipo = {
  'ONT': 'ONT',
  'DECO': 'decodificador',
  'EXTENSOR': 'extensor',
};

/// Corrobora que los equipos cargados desde TOA cumplan los mínimos de la
/// receta. [equiposPorTipo] = tipo_equipo → cantidad cargada.
/// Retorna un mensaje de error o null.
String? validarEquiposToa({
  required String tipoActividad,
  required Map<String, int> equiposPorTipo,
}) {
  final minimos = consumoMinimosEquipos(tipoActividad);
  for (final e in minimos.entries) {
    final cargados = equiposPorTipo[e.key] ?? 0;
    if (cargados < e.value) {
      final nombre = kNombreTipoEquipo[e.key] ?? e.key;
      return 'Esta actividad exige mínimo ${e.value} $nombre registrada en '
          'TOA y esta orden tiene $cargados.\n\n'
          'Si el equipo sí se instaló, el registro aún no llega a la base — '
          'reintenta más tarde o avisa a tu supervisor.';
    }
  }
  return null;
}

/// Valida los totales antes de enviar. Retorna un mensaje de error o null.
/// Solo aplica a materiales; los equipos seriados vienen de TOA y no se
/// validan aquí.
String? validarConsumoCantidades({
  required String tipoActividad,
  required Map<String, int> totalPorCategoria,
}) {
  final reglas = _reglasPara(tipoRecetaPara(tipoActividad));

  // Mínimos de la receta activa
  for (final r in reglas) {
    final min = r.minimo;
    if (min == null || min <= 0) continue;
    final total = totalPorCategoria[r.categoria] ?? 0;
    if (total < min) {
      return 'Esta actividad exige mínimo $min × ${r.categoria} '
          '(llevas $total).';
    }
  }

  // Máximos por categoría
  for (final e in totalPorCategoria.entries) {
    final max = consumoMaximo(e.key, tipoActividad);
    if (max != null && e.value > max) {
      return 'Máximo $max × ${e.key} para esta actividad (llevas ${e.value}).';
    }
  }

  // Grupo drop: mínimo y máximo del total
  var drops = 0;
  for (final cat in kConsumoCategoriasDrop) {
    drops += totalPorCategoria[cat] ?? 0;
  }
  final minDrop = consumoMinDropTotal(tipoActividad);
  if (drops < minDrop) {
    return 'Esta actividad exige $minDrop drop (de cualquier largo).';
  }
  if (drops > kConsumoMaxDropTotal) {
    return 'Solo se permite $kConsumoMaxDropTotal drop por orden '
        '(llevas $drops).';
  }

  return null;
}
