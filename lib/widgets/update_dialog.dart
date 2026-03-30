import 'package:flutter/material.dart';
import 'package:trazabox/services/update_service.dart';

enum _UpdateUiPhase { idle, downloading, installing, error }

/// Diálogo obligatorio de actualización (no se cierra con atrás ni tocando fuera).
class UpdateRequiredDialog extends StatefulWidget {
  const UpdateRequiredDialog({
    super.key,
    required this.displayVersion,
    required this.downloadUrl,
  });

  final String displayVersion;
  final String downloadUrl;

  @override
  State<UpdateRequiredDialog> createState() => _UpdateRequiredDialogState();
}

class _UpdateRequiredDialogState extends State<UpdateRequiredDialog> {
  final UpdateService _service = UpdateService();

  _UpdateUiPhase _phase = _UpdateUiPhase.idle;
  double _progress = 0;
  String? _errorMessage;

  Future<void> _onActualizarAhora() async {
    setState(() {
      _phase = _UpdateUiPhase.downloading;
      _progress = 0;
      _errorMessage = null;
    });

    try {
      await _service.downloadAndInstall(
        widget.downloadUrl,
        (p) {
          if (!mounted) return;
          setState(() => _progress = p.clamp(0.0, 1.0));
        },
        onInstalling: () {
          if (!mounted) return;
          setState(() => _phase = _UpdateUiPhase.installing);
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _UpdateUiPhase.error;
          _errorMessage = e is StateError ? e.message : e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
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
                color: const Color(0xFF00D9FF).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.system_update, color: Color(0xFF00D9FF)),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Actualización obligatoria',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nueva versión: ${widget.displayVersion}',
              style: const TextStyle(
                color: Color(0xFF00D9FF),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _phase == _UpdateUiPhase.downloading
                  ? 'Descargando…'
                  : _phase == _UpdateUiPhase.installing
                      ? 'Abriendo el instalador del sistema…'
                      : 'Debes actualizar para continuar usando TrazaBox.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 14,
              ),
            ),
            if (_phase == _UpdateUiPhase.downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF00D9FF)),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
            if (_phase == _UpdateUiPhase.installing) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(
                backgroundColor: Color(0x14FFFFFF),
                valueColor: AlwaysStoppedAnimation(Color(0xFF00D9FF)),
              ),
            ],
            if (_phase == _UpdateUiPhase.error && _errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: Color(0xFFFF6B35),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_phase != _UpdateUiPhase.downloading &&
              _phase != _UpdateUiPhase.installing)
            ElevatedButton(
              onPressed: (_phase == _UpdateUiPhase.idle ||
                      _phase == _UpdateUiPhase.error)
                  ? _onActualizarAhora
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D9FF),
                foregroundColor: Colors.white,
              ),
              child: Text(
                _phase == _UpdateUiPhase.error
                    ? 'Reintentar'
                    : 'Actualizar ahora',
              ),
            ),
        ],
      ),
    );
  }
}
