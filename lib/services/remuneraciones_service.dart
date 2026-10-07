import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class RemuneracionesService {
  static const _baseUrl = 'https://bonostraza.sbip.cl';
  static const _token = 'kduQkhT0kgHa2Ki6DmYD';
  static const _headers = {'Authorization': 'Bearer $_token'};

  /// Verifica si hay datos de bono para el técnico en ese mes (para el badge).
  /// [tipoContrato]: 'nuevo' → /api/cn/bonos, 'antiguo' → /api/ca/bonos
  Future<({Map<String, dynamic>? data, int statusCode, String errorMsg})> obtenerBonosTecnico({
    required String rut,
    required String tipoContrato,
    required String mes,
  }) async {
    try {
      final path = tipoContrato == 'antiguo' ? '/api/ca/bonos' : '/api/cn/bonos';
      final response = await http.get(
        Uri.parse('$_baseUrl$path?mes=$mes'),
        headers: _headers,
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        return (data: null, statusCode: response.statusCode, errorMsg: '');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (decoded['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      final rutNorm = _normRut(rut);
      for (final t in list) {
        if (_normRut(t['rut']?.toString() ?? '') == rutNorm) {
          return (data: t, statusCode: 200, errorMsg: '');
        }
      }
      return (data: null, statusCode: 200, errorMsg: '');
    } on SocketException catch (e) {
      return (data: null, statusCode: 0, errorMsg: 'Red: ${e.message}');
    } on TimeoutException {
      return (data: null, statusCode: 0, errorMsg: 'Timeout (20s)');
    } on HandshakeException catch (e) {
      return (data: null, statusCode: 0, errorMsg: 'SSL: ${e.message}');
    } on FormatException catch (e) {
      return (data: null, statusCode: 0, errorMsg: 'Respuesta inválida: ${e.message}');
    } catch (e) {
      return (data: null, statusCode: 0, errorMsg: '${e.runtimeType}: $e');
    }
  }

  /// Descarga el PDF del anexo de remuneraciones para un técnico y mes.
  /// Retorna los bytes del PDF o null si falla.
  Future<({Uint8List? bytes, String errorMsg})> descargarAnexoPdf({
    required String rut,
    required String mes,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/anexo/pdf?rut=$rut&mes=$mes'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return (bytes: response.bodyBytes, errorMsg: '');
      }
      return (bytes: null, errorMsg: 'Error ${response.statusCode}');
    } on SocketException catch (e) {
      return (bytes: null, errorMsg: 'Red: ${e.message}');
    } on TimeoutException {
      return (bytes: null, errorMsg: 'Timeout (30s)');
    } catch (e) {
      return (bytes: null, errorMsg: '${e.runtimeType}');
    }
  }

  /// Últimos [n] meses en formato YYYY-MM, del más reciente al más antiguo.
  static List<String> ultimosMeses(int n) {
    final now = DateTime.now();
    return List.generate(n, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    });
  }

  static String _normRut(String rut) =>
      rut.replaceAll('.', '').replaceAll('-', '').toUpperCase();
}
