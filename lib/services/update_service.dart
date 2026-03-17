import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';

/// Servicio para verificar e instalar actualizaciones desde GitHub Releases
class UpdateService {
  // GitHub repository for auto-updates
  static const String _githubRepo = 'karimpichara/trazabox';
  static const String _apiUrl = 'https://api.github.com/repos';

  final Dio _dio = Dio();

  /// Verifica si hay una actualización disponible
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 1;

      print('📦 Versión actual: ${packageInfo.version}+$currentVersionCode');

      // Obtener el último release de GitHub
      final response = await _dio.get(
        '$_apiUrl/$_githubRepo/releases/latest',
        options: Options(headers: {'Accept': 'application/vnd.github.v3+json'}),
      );

      if (response.statusCode != 200) {
        print('⚠️ Error obteniendo releases: ${response.statusCode}');
        return null;
      }

      final data = response.data;
      final tagName = data['tag_name'] as String?;
      final releaseNotes = data['body'] as String?;
      final assets = data['assets'] as List?;

      if (tagName == null || assets == null) {
        print('⚠️ Release sin tag o assets');
        return null;
      }

      // Buscar el APK en los assets
      final apkAsset = assets.cast<Map>().firstWhere(
        (asset) => (asset['name'] as String).endsWith('.apk'),
        orElse: () => <String, dynamic>{},
      );

      if (apkAsset.isEmpty) {
        print('⚠️ No se encontró APK en el release');
        return null;
      }

      // Extraer versionCode del tag (formato: v1.0.0+5 o 1.0.0+5)
      final versionCode = _extractVersionCode(tagName);

      print('🔄 Última versión en GitHub: $tagName (code: $versionCode)');

      if (versionCode > currentVersionCode) {
        return UpdateInfo(
          versionName: tagName,
          versionCode: versionCode,
          downloadUrl: apkAsset['browser_download_url'] as String,
          releaseNotes: releaseNotes ?? 'Nueva versión disponible',
          fileSize: (apkAsset['size'] as int?) ?? 0,
        );
      }

      print('✅ App actualizada');
      return null;
    } catch (e) {
      print('❌ Error verificando actualizaciones: $e');
      return null;
    }
  }

  /// Extrae el versionCode de un tag (v1.0.0+5 -> 5)
  int _extractVersionCode(String tag) {
    // Formatos soportados: v1.0.0+5, 1.0.0+5, v1.0.0-5
    final match = RegExp(r'[+\-](\d+)$').firstMatch(tag);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }

  /// Descarga el APK y retorna la ruta del archivo
  Future<String?> downloadApk(String url, Function(double progress)? onProgress) async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) {
        print('❌ No se pudo obtener directorio de almacenamiento');
        return null;
      }

      final filePath = '${dir.path}/trazabox_update.apk';
      final file = File(filePath);

      // Eliminar archivo anterior si existe
      if (await file.exists()) {
        await file.delete();
      }

      print('⬇️ Descargando APK desde: $url');

      await _dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );

      print('✅ APK descargado: $filePath');
      return filePath;
    } catch (e) {
      print('❌ Error descargando APK: $e');
      return null;
    }
  }

  /// Instala el APK
  Future<bool> installApk(String filePath) async {
    try {
      // Verificar permiso de instalación
      if (Platform.isAndroid) {
        final status = await Permission.requestInstallPackages.request();
        if (!status.isGranted) {
          print('❌ Permiso de instalación denegado');
          return false;
        }
      }

      print('📦 Instalando APK: $filePath');
      final result = await OpenFile.open(filePath);

      if (result.type != ResultType.done) {
        print('❌ Error abriendo APK: ${result.message}');
        return false;
      }

      return true;
    } catch (e) {
      print('❌ Error instalando APK: $e');
      return false;
    }
  }
}

/// Información de una actualización disponible
class UpdateInfo {
  final String versionName;
  final int versionCode;
  final String downloadUrl;
  final String releaseNotes;
  final int fileSize;

  UpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.fileSize,
  });

  String get fileSizeFormatted {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Widget de diálogo para mostrar actualización disponible
class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  final UpdateService updateService;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    required this.updateService,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0A1628),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF00D9FF), width: 1),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00D9FF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.system_update,
              color: Color(0xFF00D9FF),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Actualización disponible',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nueva versión: ${widget.updateInfo.versionName}',
            style: const TextStyle(
              color: Color(0xFF00D9FF),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tamaño: ${widget.updateInfo.fileSizeFormatted}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.updateInfo.releaseNotes,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 13,
              ),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_isDownloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF00D9FF)),
            ),
            const SizedBox(height: 8),
            Text(
              'Descargando... ${(_progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFFF6B35),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (!_isDownloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Después',
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ),
          ),
        if (!_isDownloading)
          ElevatedButton(
            onPressed: _downloadAndInstall,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D9FF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Actualizar ahora'),
          ),
      ],
    );
  }

  Future<void> _downloadAndInstall() async {
    setState(() {
      _isDownloading = true;
      _error = null;
    });

    try {
      final filePath = await widget.updateService.downloadApk(
        widget.updateInfo.downloadUrl,
        (progress) {
          setState(() => _progress = progress);
        },
      );

      if (filePath == null) {
        setState(() {
          _isDownloading = false;
          _error = 'Error al descargar la actualización';
        });
        return;
      }

      final installed = await widget.updateService.installApk(filePath);
      if (!installed) {
        setState(() {
          _isDownloading = false;
          _error = 'Error al instalar la actualización';
        });
        return;
      }

      // Si llegamos aquí, la instalación inició
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _error = 'Error: $e';
      });
    }
  }
}

/// Función helper para mostrar el diálogo de actualización
Future<bool?> showUpdateDialog(BuildContext context, UpdateInfo updateInfo) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => UpdateDialog(
      updateInfo: updateInfo,
      updateService: UpdateService(),
    ),
  );
}
