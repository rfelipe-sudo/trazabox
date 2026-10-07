/// Un material del inventario personal de un técnico, según la API
/// logística de TRAZA (endpoint `/stocks/inventario/por-rut/{rut}`).
///
/// Ejemplo de JSON que devuelve la API:
/// ```json
/// {
///   "rutTrabajador": "17926483-8",
///   "materialId": 2037,
///   "nombreMaterial": "CELULAR SAMSUNG GALAXY A30s",
///   "skuMaterial": "CP-0106-0023-01376",
///   "nombreFamilia": "COMPUTACION E INFORMATICA",
///   "esSeriado": true,
///   "cantidadEnInventario": 1,
///   "series": ["355049112498884"]
/// }
/// ```
class InventarioMaterial {
  final String rutTrabajador;
  final int materialId;
  final String nombreMaterial;
  final String skuMaterial;

  /// Categoría del material, ej: "INSTALACIONES DOMICILIARIAS",
  /// "PROTECCION PERSONAL", "HERRAMIENTAS MENORES".
  final String nombreFamilia;

  /// true si el material se controla por número de serie (ej: celulares,
  /// notebooks). En ese caso [series] trae las series en su poder.
  final bool esSeriado;

  final num cantidadEnInventario;

  /// Números de serie (solo para materiales seriados con stock).
  final List<String> series;

  const InventarioMaterial({
    required this.rutTrabajador,
    required this.materialId,
    required this.nombreMaterial,
    required this.skuMaterial,
    required this.nombreFamilia,
    required this.esSeriado,
    required this.cantidadEnInventario,
    required this.series,
  });

  /// true si el técnico tiene al menos una unidad.
  bool get tieneStock => cantidadEnInventario > 0;

  factory InventarioMaterial.fromJson(Map<String, dynamic> json) {
    return InventarioMaterial(
      rutTrabajador: json['rutTrabajador'] ?? '',
      materialId: json['materialId'] ?? 0,
      nombreMaterial: json['nombreMaterial'] ?? '',
      skuMaterial: json['skuMaterial'] ?? '',
      nombreFamilia: json['nombreFamilia'] ?? '',
      esSeriado: json['esSeriado'] ?? false,
      cantidadEnInventario: json['cantidadEnInventario'] ?? 0,
      series: (json['series'] as List?)?.map((s) => s.toString()).toList() ??
          const [],
    );
  }
}
