import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Un equipo seriado registrado por el técnico en TOA al cerrar la actividad.
class EquipoInstaladoToa {
  /// Nombre del material según traza materiales (o el tipo si no cruzó).
  final String descripcion;
  final String serie;

  /// ONT | DECO | EXTENSOR | GATEWAY | MTA | OTRO
  final String categoria;

  const EquipoInstaladoToa({
    required this.descripcion,
    required this.serie,
    required this.categoria,
  });
}

/// Lee los equipos seriados por OT desde la tabla `equipos_seriados_traza`
/// de Supabase — el histórico permanente que se alimenta a diario desde la
/// sábana TOA (APPSCRIPT_EQUIPOS_SERIADOS_TRAZA.js), porque la sábana en
/// vivo se extingue cada día.
class KeplerSabanaService {
  Future<List<EquipoInstaladoToa>> equiposInstalados(
      String ordenTrabajo) async {
    try {
      final rows = await Supabase.instance.client
          .from('equipos_seriados_traza')
          .select('tipo_equipo, serie, descripcion')
          .eq('orden_trabajo', ordenTrabajo);

      return (rows as List)
          .map((r) => EquipoInstaladoToa(
                descripcion: (r['descripcion'] as String?)?.isNotEmpty == true
                    ? r['descripcion'] as String
                    : (r['tipo_equipo'] as String? ?? 'Equipo'),
                serie: r['serie'] as String? ?? '',
                categoria: r['tipo_equipo'] as String? ?? 'OTRO',
              ))
          .where((e) => e.serie.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[EquiposSeriados] error consultando $ordenTrabajo: $e');
      return const [];
    }
  }
}
