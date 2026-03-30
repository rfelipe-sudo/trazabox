import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// URL de la última release (API pública GitHub).
const String kGitHubLatestReleaseUrl =
    'https://api.github.com/repos/rfelipe-sudo/trazabox/releases/latest';

const String kGitHubApkAssetName = 'app-release.apk';

const String kUpdateApkFileName = 'update.apk';

// ─── Resultado de checkForUpdate ───────────────────────────────────────────

sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// No hay actualización o la remota no es mayor que la instalada.
class UpdateCheckUpToDate extends UpdateCheckResult {
  const UpdateCheckUpToDate();
}

/// Hay una versión más nueva en GitHub.
class UpdateCheckAvailable extends UpdateCheckResult {
  final String remoteTag;
  final String displayVersion;
  final String downloadUrl;

  const UpdateCheckAvailable({
    required this.remoteTag,
    required this.displayVersion,
    required this.downloadUrl,
  });
}

/// Sin red / timeout / host unreachable.
class UpdateCheckNoConnection extends UpdateCheckResult {
  final Object? cause;

  const UpdateCheckNoConnection([this.cause]);
}

/// Respuesta inválida o asset APK no encontrado.
class UpdateCheckError extends UpdateCheckResult {
  final String message;

  const UpdateCheckError(this.message);
}

/// Borra el APK en segundo plano: 3s, luego +5s, +10s, +30s entre intentos; no bloquea la UI.
void _scheduleDeleteUpdateApk(File file) {
  unawaited(_deleteUpdateApkWithRetries(file));
}

Future<void> _deleteUpdateApkWithRetries(File file) async {
  const delays = <Duration>[
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];
  for (final d in delays) {
    await Future<void>.delayed(d);
    try {
      if (await file.exists()) {
        await file.delete();
      }
      if (!await file.exists()) return;
    } catch (_) {}
  }
}

/// Servicio de actualización desde GitHub Releases.
class UpdateService {
  UpdateService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Quita prefijo `v`/`V` y compara semver (major.minor.patch).
  /// Retorna `true` si [remoteTag] es **estrictamente mayor** que [currentVersion].
  static bool isRemoteNewerThanCurrent(String remoteTag, String currentVersion) {
    return compareSemver(remoteTag, currentVersion) > 0;
  }

  /// < 0 si a < b, 0 si igual, > 0 si a > b.
  static int compareSemver(String a, String b) {
    final pa = _parseSemverParts(a);
    final pb = _parseSemverParts(b);
    for (var i = 0; i < 3; i++) {
      final c = pa[i].compareTo(pb[i]);
      if (c != 0) return c;
    }
    return 0;
  }

  static List<int> _parseSemverParts(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1);
    }
    final parts = s.split('.');
    int p(int i) {
      if (i >= parts.length) return 0;
      final seg = parts[i];
      final match = RegExp(r'^(\d+)').firstMatch(seg);
      return int.tryParse(match?.group(1) ?? '') ?? 0;
    }

    return [p(0), p(1), p(2)];
  }

  /// Consulta GitHub y compara con [PackageInfo.version] (sin build).
  Future<UpdateCheckResult> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final current = packageInfo.version.trim();

      final uri = Uri.parse(kGitHubLatestReleaseUrl);
      final response = await http
          .get(
            uri,
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'TrazaBox-Flutter-Update',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        return UpdateCheckError(
          'GitHub respondió ${response.statusCode}',
        );
      }

      final dynamic data;
      try {
        data = jsonDecode(response.body);
      } on FormatException catch (e) {
        return UpdateCheckError('JSON inválido: $e');
      }
      if (data is! Map<String, dynamic>) {
        return const UpdateCheckError('Respuesta JSON inválida');
      }

      final tagName = data['tag_name']?.toString().trim();
      if (tagName == null || tagName.isEmpty) {
        return const UpdateCheckError('Release sin tag_name');
      }

      String? downloadUrl;
      final assets = data['assets'];
      if (assets is List) {
        for (final item in assets) {
          if (item is Map<String, dynamic> &&
              item['name']?.toString() == kGitHubApkAssetName) {
            downloadUrl = item['browser_download_url']?.toString();
            break;
          }
        }
      }

      if (downloadUrl == null || downloadUrl.isEmpty) {
        return UpdateCheckError(
          'No se encontró el asset "$kGitHubApkAssetName" en la release',
        );
      }

      if (!isRemoteNewerThanCurrent(tagName, current)) {
        return const UpdateCheckUpToDate();
      }

      return UpdateCheckAvailable(
        remoteTag: tagName,
        displayVersion: tagName,
        downloadUrl: downloadUrl,
      );
    } on SocketException catch (e) {
      return UpdateCheckNoConnection(e);
    } on http.ClientException catch (e) {
      return UpdateCheckNoConnection(e);
    } on HttpException catch (e) {
      return UpdateCheckNoConnection(e);
    } on HandshakeException catch (e) {
      return UpdateCheckNoConnection(e);
    } on TlsException catch (e) {
      return UpdateCheckNoConnection(e);
    } on TimeoutException catch (e) {
      return UpdateCheckNoConnection(e);
    } catch (e) {
      return UpdateCheckError(e.toString());
    }
  }

  /// Descarga [url] a [getTemporaryDirectory]/[kUpdateApkFileName], abre el instalador y borra el APK.
  ///
  /// [onProgress]: 0.0–1.0 durante la descarga; al terminar la descarga se emite 1.0 antes de abrir el instalador.
  /// [onInstalling]: se invoca justo antes de abrir el instalador del sistema.
  Future<void> downloadAndInstall(
    String url,
    void Function(double progress) onProgress, {
    void Function()? onInstalling,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'La instalación automática solo está soportada en Android',
      );
    }

    try {
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) {
        throw StateError(
          'Se necesita permiso para instalar actualizaciones. '
          'Actívalo en Ajustes de la aplicación.',
        );
      }

      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/$kUpdateApkFileName';
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
      }

      onProgress(0);

      await _dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress((received / total).clamp(0.0, 1.0));
          } else if (received > 0) {
            onProgress(0);
          }
        },
        options: Options(
          headers: const {
            'Accept': 'application/octet-stream',
            'User-Agent': 'TrazaBox-Flutter-Update',
          },
          followRedirects: true,
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );

      onProgress(1);
      onInstalling?.call();

      final result = await OpenFile.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done) {
        throw StateError(
          result.message.isNotEmpty
              ? result.message
              : 'No se pudo abrir el instalador',
        );
      }

      _scheduleDeleteUpdateApk(file);
    } on DioException catch (e) {
      final msg = e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout
          ? 'Sin conexión o tiempo de espera agotado al descargar.'
          : 'Error al descargar: ${e.message ?? e.toString()}';
      throw StateError(msg);
    }
  }
}
