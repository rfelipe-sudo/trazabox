import 'package:flutter/material.dart';

/// Widget visual del ícono de la app TrazaBox (1024×1024, estilo squircle iOS).
/// Usar con RepaintBoundary + RenderRepaintBoundary.toImage() para exportar PNG.
class AppIconWidget extends StatelessWidget {
  final double size;
  const AppIconWidget({super.key, this.size = 1024});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.225),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _IconPainter(),
          child: Stack(
            children: [
              // Emoji técnico principal
              Positioned(
                left: size * 0.06,
                top: size * 0.088,
                child: Image.asset(
                  'assets/images/emoji_tecnico.png',
                  width: size * 0.879,
                  height: size * 0.879,
                  fit: BoxFit.contain,
                ),
              ),
              // Badge TB — esquina superior derecha
              Positioned(
                right: size * 0.02,
                top: size * 0.039,
                child: CustomPaint(
                  size: Size(size * 0.342, size * 0.191),
                  painter: _BadgePainter(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pinta el fondo degradado, glow naranja inferior y glow cyan detrás del badge.
class _IconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Fondo gradiente diagonal
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0B1D60),
            Color(0xFF1449C6),
            Color(0xFF0A2A80),
          ],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Glow naranja inferior difuminado
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.73),
        width: size.width * 0.78,
        height: size.height * 0.59,
      ),
      Paint()
        ..color = const Color(0x1FFF9E28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80),
    );

    // Glow cyan detrás del badge (decorativo)
    canvas.drawCircle(
      Offset(size.width * 0.81, size.height * 0.176),
      size.width * 0.09,
      Paint()
        ..color = const Color(0x1A00E5FF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Pinta el badge "TB" con letra T blanca y B cyan outline.
class _BadgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(h * 0.27),
    );

    // Fondo semitransparente azul oscuro
    canvas.drawRRect(rrect, Paint()..color = const Color(0xEB0A1450));

    // Borde cyan sutil
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0x6600E5FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ── Letra T ──────────────────────────────────────────────────
    // Barra horizontal
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.085, h * 0.225, w * 0.298, h * 0.266),
        const Radius.circular(8),
      ),
      Paint()..color = Colors.white,
    );
    // Barra vertical
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.200, h * 0.490, w * 0.115, h * 0.420),
        const Radius.circular(10),
      ),
      Paint()..color = Colors.white,
    );

    // ── Letra B ──────────────────────────────────────────────────
    final bX = w * 0.575;

    // Línea vertical blanca
    canvas.drawLine(
      Offset(bX, h * 0.225),
      Offset(bX, h * 0.775),
      Paint()
        ..color = Colors.white
        ..strokeWidth = w * 0.13
        ..strokeCap = StrokeCap.round,
    );

    // Curvas cyan outline
    final curvePaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = w * 0.092
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Curva superior B
    canvas.drawPath(
      Path()
        ..moveTo(bX, h * 0.225)
        ..cubicTo(bX + w * 0.28, h * 0.225, bX + w * 0.28, h * 0.500, bX, h * 0.500),
      curvePaint,
    );

    // Curva inferior B
    canvas.drawPath(
      Path()
        ..moveTo(bX, h * 0.500)
        ..cubicTo(bX + w * 0.30, h * 0.500, bX + w * 0.30, h * 0.775, bX, h * 0.775),
      curvePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
