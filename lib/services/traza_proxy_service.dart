import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';
import '../models/inventario_material.dart';

/// Cliente HTTP para la API logística de TRAZA (apilogistica.traza.cl),
/// consumida a través del proxy `proxy-traza.sbip.cl`.
///
/// ¿Por qué un proxy? La API de traza está detrás de Cloudflare con
/// "managed challenge": rechaza peticiones que no parezcan de un navegador
/// real, y una app móvil no puede resolver ese desafío. El proxy (un servidor
/// en AWS Lightsail) recibe nuestra petición, le inyecta headers de navegador
/// Chrome y la reenvía a la API real.
///
/// Reglas del proxy:
/// - Toda petición debe llevar el header `X-API-Key` (si no, responde 401).
/// - Las rutas se mapean 1 a 1: pedir `/stocks/...` al proxy equivale a
///   pedir `/stocks/...` a apilogistica.traza.cl.
/// - El proxy espera hasta 30 segundos la respuesta de traza, por eso
///   nuestro timeout es un poco mayor (35 s).
class TrazaProxyService {
  /// Timeout mayor que el del proxy (30 s) para no cortar antes que él.
  static const Duration _timeout = Duration(seconds: 35);

  Map<String, String> get _headers => {
        'X-API-Key': AppConstants.trazaProxyApiKey,
        'Accept': 'application/json',
      };

  /// Verifica que el proxy esté vivo. No requiere la llave.
  /// Útil para diagnosticar: si esto falla, el problema es de red o del
  /// servidor proxy, no de la llave.
  Future<bool> probarConexion() async {
    try {
      final response = await http
          .get(Uri.parse('${AppConstants.trazaProxyBaseUrl}/healthz'))
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      print('❌ [TrazaProxy] Sin conexión con el proxy: $e');
      return false;
    }
  }

  /// GET genérico a cualquier ruta de la API de traza.
  ///
  /// [path] debe empezar con `/`, por ejemplo:
  /// `get('/stocks/inventario/por-rut/17926483-8')`
  ///
  /// Devuelve el JSON ya parseado (puede ser Map o List según el endpoint).
  /// Lanza [TrazaProxyException] si la respuesta no es 200.
  Future<dynamic> get(String path) async {
    final uri = Uri.parse('${AppConstants.trazaProxyBaseUrl}$path');

    final response = await http.get(uri, headers: _headers).timeout(_timeout);

    if (response.statusCode == 401) {
      throw TrazaProxyException(
        'Llave X-API-Key inválida o no configurada. '
        'Revisa AppConstants.trazaProxyApiKey.',
        statusCode: 401,
      );
    }

    if (response.statusCode != 200) {
      throw TrazaProxyException(
        'Error ${response.statusCode} al pedir $path: ${response.body}',
        statusCode: response.statusCode,
      );
    }

    return jsonDecode(response.body);
  }

  /// POST genérico a la API de traza (vía proxy). Devuelve el JSON parseado.
  /// Lanza [TrazaProxyException] si la respuesta no es 2xx.
  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('${AppConstants.trazaProxyBaseUrl}$path');

    final response = await http
        .post(
          uri,
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    if (response.statusCode == 401) {
      throw TrazaProxyException(
        'Llave X-API-Key inválida o no configurada.',
        statusCode: 401,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TrazaProxyException(
        'Error ${response.statusCode} en POST $path: ${response.body}',
        statusCode: response.statusCode,
      );
    }
    return jsonDecode(response.body);
  }

  /// Inventario de materiales de un técnico según su RUT.
  ///
  /// El RUT va con guión y dígito verificador, ej: `17926483-8`.
  /// Devuelve TODOS los materiales asignados alguna vez a su bodega
  /// personal (incluso con cantidad 0); filtra con `tieneStock` si solo
  /// quieres lo que tiene ahora.
  ///
  /// La API de traza tiene solo 2 endpoints (según su openapi.json):
  /// este, y `/stocks/por-rut/{rut}` que trae lo mismo pero con mucho
  /// más detalle anidado (bodega, artículo, familia, códigos por cliente).
  Future<List<InventarioMaterial>> obtenerInventarioPorRut(String rut) async {
    final data = await get('/stocks/inventario/por-rut/$rut');

    if (data is! List) {
      throw TrazaProxyException(
        'Se esperaba una lista de materiales y llegó: ${data.runtimeType}',
      );
    }

    return data
        .map((item) => InventarioMaterial.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}

/// Error de la API de traza con el código HTTP que lo causó.
class TrazaProxyException implements Exception {
  final String message;
  final int? statusCode;

  TrazaProxyException(this.message, {this.statusCode});

  @override
  String toString() => 'TrazaProxyException: $message';
}
