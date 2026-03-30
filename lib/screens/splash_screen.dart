import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:trazabox/services/update_service.dart';
import 'package:trazabox/widgets/update_dialog.dart';

// ─── Paleta ──────────────────────────────────────────────────────────────────
const _bg     = Color(0xFF050810);
const _cyan   = Color(0xFF00E5FF);
const _blue   = Color(0xFF1449C6);
const _green  = Color(0xFF00C49A);
const _pink   = Color(0xFFE83E8C);
const _orange = Color(0xFFFF7A2F);

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// Debe coincidir con [MaterialApp.initialRoute] — primer destino al abrir la app.
  static const String routeName = '/splash';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  // Aurora 12s
  late final AnimationController _aurora;
  late final Animation<double> _auroraRot;
  late final Animation<double> _auroraScale;

  // Glow 8s
  late final AnimationController _glow;

  // Texto: "BIENVENIDO A"
  late final AnimationController _bienCtrl;
  late final Animation<double> _bienFade;
  late final Animation<Offset> _bienSlide;

  // Letras de "TRAZABOX" — animación escalonada
  late final AnimationController _letrasCtrl;
  final String _letras = 'TRAZABOX';

  // Elementos estáticos
  late final AnimationController _dividerCtrl;
  late final AnimationController _dotsCtrl;
  late final AnimationController _barFadeCtrl;
  late final AnimationController _footerCtrl;

  // Barra
  late final AnimationController _progress;
  late final Animation<double> _progressAnim;

  // Dots pulsantes
  late final List<AnimationController> _dotPulse;

  bool _navegado = false;

  /// Consulta GitHub en paralelo a la animación; antes de /home siempre se espera en _runUpdateGate.
  late Future<UpdateCheckResult> _updateCheckFuture;

  @override
  void initState() {
    super.initState();
    _updateCheckFuture = UpdateService.checkForUpdate();

    // Aurora
    _aurora = AnimationController(vsync: this, duration: const Duration(seconds: 12))
      ..repeat(reverse: true);
    _auroraRot = Tween<double>(begin: -5 * math.pi / 180, end: 8 * math.pi / 180)
        .animate(CurvedAnimation(parent: _aurora, curve: Curves.easeInOut));
    _auroraScale = Tween<double>(begin: 0.97, end: 1.05)
        .animate(CurvedAnimation(parent: _aurora, curve: Curves.easeInOut));

    // Glow
    _glow = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..repeat(reverse: true);

    // "BIENVENIDO A" — aparece en 600ms con delay 200ms
    _bienCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _bienFade  = CurvedAnimation(parent: _bienCtrl, curve: Curves.easeOut);
    _bienSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _bienCtrl, curve: Curves.easeOutCubic));
    Future.delayed(const Duration(milliseconds: 200), () { if (mounted) _bienCtrl.forward(); });

    // "TRAZABOX" — 8 letras en 1200ms, delay 400ms
    _letrasCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    Future.delayed(const Duration(milliseconds: 400), () { if (mounted) _letrasCtrl.forward(); });

    // Divider, dots, barra, footer
    _dividerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _dotsCtrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _barFadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _footerCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

    Future.delayed(const Duration(milliseconds: 2000), () { if (mounted) _dividerCtrl.forward(); });
    Future.delayed(const Duration(milliseconds: 2200), () { if (mounted) _dotsCtrl.forward(); });
    Future.delayed(const Duration(milliseconds: 2400), () { if (mounted) _barFadeCtrl.forward(); });
    Future.delayed(const Duration(milliseconds: 2800), () { if (mounted) _footerCtrl.forward(); });

    // Barra 3s, comienza cuando aparece
    _progress = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));
    _progressAnim = CurvedAnimation(parent: _progress, curve: Curves.easeInOut);
    Future.delayed(const Duration(milliseconds: 2600), () { if (mounted) _progress.forward(); });

    _progress.addStatusListener((s) {
      if (s == AnimationStatus.completed && !_navegado && mounted) {
        _navegado = true;
        Future.delayed(const Duration(milliseconds: 300), _navegar);
      }
    });

    // Dots pulsantes
    _dotPulse = List.generate(3, (i) {
      final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
      Future.delayed(Duration(milliseconds: 2400 + i * 400), () {
        if (mounted) c.repeat(reverse: true);
      });
      return c;
    });
  }

  Future<void> _navegar() async {
    if (!mounted) return;

    // Obligatorio: comprobar actualización (y diálogos) antes de cualquier otra pantalla, con o sin técnico en sesión.
    final puedeEntrar = await _runUpdateGate();

    if (!mounted) return;
    if (puedeEntrar) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  /// `true` si puede continuar a la app principal (al día o flujo de actualización completado).
  Future<bool> _runUpdateGate() async {
    var result = await _updateCheckFuture;
    if (!mounted) return false;

    while (mounted) {
      if (result is UpdateCheckUpToDate) {
        return true;
      }

      if (result is UpdateCheckAvailable) {
        // Variable local: dentro del `builder` no aplica la promoción de tipo de `result`.
        final available = result;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => UpdateRequiredDialog(
            displayVersion: available.displayVersion,
            downloadUrl: available.downloadUrl,
          ),
        );
        if (!mounted) return false;
        return true;
      }

      final titulo = result is UpdateCheckNoConnection
          ? 'Sin conexión'
          : 'No se pudo verificar';
      final mensaje = result is UpdateCheckNoConnection
          ? 'Comprueba tu conexión a internet e intenta de nuevo.'
          : (result as UpdateCheckError).message;

      final reintentar = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF0A1628),
            title: Text(
              titulo,
              style: const TextStyle(color: Colors.white),
            ),
            content: Text(
              mensaje,
              style: const TextStyle(color: Color(0xFF8FA8C8)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );

      if (reintentar != true || !mounted) {
        return false;
      }

      _updateCheckFuture = UpdateService.checkForUpdate();
      result = await _updateCheckFuture;
    }
    return false;
  }

  @override
  void dispose() {
    _aurora.dispose(); _glow.dispose();
    _bienCtrl.dispose(); _letrasCtrl.dispose();
    _dividerCtrl.dispose(); _dotsCtrl.dispose();
    _barFadeCtrl.dispose(); _footerCtrl.dispose();
    _progress.dispose();
    for (final c in _dotPulse) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size  = MediaQuery.of(context).size;
    final w     = size.width;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // ── Dot grid ─────────────────────────────────────────────────────
          CustomPaint(size: size, painter: _DotGridPainter()),

          // ── Scanlines ────────────────────────────────────────────────────
          CustomPaint(size: size, painter: _ScanlinesPainter()),

          // ── Línea diagonal ────────────────────────────────────────────────
          Positioned(
            right: 80, top: 0, bottom: 0,
            child: Container(
              width: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    _cyan.withOpacity(0.15),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // ── Aurora ────────────────────────────────────────────────────────
          AnimatedBuilder(
            animation: _aurora,
            builder: (_, __) => Positioned(
              top: -w * 0.35, left: -w * 0.35,
              child: Transform.rotate(
                angle: _auroraRot.value,
                child: Transform.scale(
                  scale: _auroraScale.value,
                  child: _AuroraWidget(size: size * 0.95),
                ),
              ),
            ),
          ),

          // ── Glow inferior ─────────────────────────────────────────────────
          AnimatedBuilder(
            animation: _glow,
            builder: (_, __) {
              final op = 0.5 + _glow.value * 0.3;
              return Positioned(
                bottom: -80, right: -60,
                child: Container(
                  width: 320, height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _green.withOpacity(op * 0.25),
                    boxShadow: [BoxShadow(
                      color: _green.withOpacity(op * 0.15),
                      blurRadius: 40, spreadRadius: 20,
                    )],
                  ),
                ),
              );
            },
          ),

          // ── Contenido central ─────────────────────────────────────────────
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // "BIENVENIDO A"
                  FadeTransition(
                    opacity: _bienFade,
                    child: SlideTransition(
                      position: _bienSlide,
                      child: Text(
                        'BIENVENIDO A',
                        style: GoogleFonts.bebasNeue(
                          fontSize: (w * 0.075).clamp(20.0, 30.0),
                          color: Colors.white.withOpacity(0.55),
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 2),

                  // "TRAZABOX" — letras escalonadas
                  _TrazaBoxLetras(
                    ctrl: _letrasCtrl,
                    letras: _letras,
                    fontSize: (w * 0.16).clamp(52.0, 76.0),
                  ),

                  const SizedBox(height: 28),

                  // Divider
                  FadeTransition(
                    opacity: _dividerCtrl,
                    child: Container(
                      width: 160, height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            _cyan.withOpacity(0.5),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Corp dots
                  FadeTransition(
                    opacity: _dotsCtrl,
                    child: _CorpDots(pulseControllers: _dotPulse),
                  ),

                  const SizedBox(height: 36),

                  // Barra de progreso
                  FadeTransition(
                    opacity: _barFadeCtrl,
                    child: AnimatedBuilder(
                      animation: _progressAnim,
                      builder: (_, __) => _ProgressBar(value: _progressAnim.value),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Footer ────────────────────────────────────────────────────────
          Positioned(
            bottom: 32, left: 0, right: 0,
            child: FadeTransition(
              opacity: _footerCtrl,
              child: Column(
                children: [
                  Text('POWERED BY', style: GoogleFonts.jetBrainsMono(
                    fontSize: 8, letterSpacing: 2.5,
                    color: Colors.white.withOpacity(0.18),
                  )),
                  const SizedBox(height: 4),
                  Text('Creaciones Tecnológicas', style: GoogleFonts.spaceGrotesk(
                    fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1,
                    color: Colors.white.withOpacity(0.32),
                  )),
                ],
              ),
            ),
          ),

        ],
      ),
    );
  }
}

// ─── Letras escalonadas de "TRAZABOX" ────────────────────────────────────────
class _TrazaBoxLetras extends StatelessWidget {
  final AnimationController ctrl;
  final String letras;
  final double fontSize;

  const _TrazaBoxLetras({
    required this.ctrl,
    required this.letras,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final n = letras.length; // 8

    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(n, (i) {
            // Cada letra arranca en i/(n*1.2) y termina en (i+1)/(n*1.2)
            final start  = i / (n * 1.2);
            final end    = (i + 1) / (n * 1.2);
            final t      = ((ctrl.value - start) / (end - start)).clamp(0.0, 1.0);
            final eased  = Curves.easeOutBack.transform(t);

            final char    = letras[i];
            // TRAZA = índices 0-4 → blanco; BOX = índices 5-7 → cyan outline
            final esBOX   = i >= 5;

            return Transform.translate(
              offset: Offset(0, 20 * (1 - eased)),
              child: Opacity(
                opacity: eased.clamp(0.0, 1.0),
                child: esBOX
                    ? Stack(
                        children: [
                          // Glow
                          Text(char, style: GoogleFonts.bebasNeue(
                            fontSize: fontSize,
                            fontWeight: FontWeight.bold,
                            foreground: Paint()
                              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
                              ..color = _cyan.withOpacity(0.6),
                          )),
                          // Outline
                          Text(char, style: GoogleFonts.bebasNeue(
                            fontSize: fontSize,
                            fontWeight: FontWeight.bold,
                            foreground: Paint()
                              ..style = PaintingStyle.stroke
                              ..strokeWidth = 1.5
                              ..color = _cyan,
                          )),
                        ],
                      )
                    : Text(char, style: GoogleFonts.bebasNeue(
                        fontSize: fontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: const [
                          Shadow(color: Colors.white24, blurRadius: 12),
                        ],
                      )),
              ),
            );
          }),
        );
      },
    );
  }
}

// ─── Aurora widget ────────────────────────────────────────────────────────────
class _AuroraWidget extends StatelessWidget {
  final Size size;
  const _AuroraWidget({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size.width, height: size.height,
      child: Stack(children: [
        Container(width: size.width, height: size.height,
          decoration: BoxDecoration(gradient: RadialGradient(
            center: Alignment.center, radius: 0.7,
            colors: [_blue.withOpacity(0.45), Colors.transparent],
          ))),
        Positioned(left: size.width * 0.2, top: size.height * 0.1,
          child: Container(width: size.width * 0.6, height: size.height * 0.6,
            decoration: BoxDecoration(gradient: RadialGradient(
              colors: [_cyan.withOpacity(0.25), Colors.transparent],
            )))),
        Positioned(right: size.width * 0.05, bottom: size.height * 0.05,
          child: Container(width: size.width * 0.4, height: size.height * 0.4,
            decoration: BoxDecoration(gradient: RadialGradient(
              colors: [_pink.withOpacity(0.18), Colors.transparent],
            )))),
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(color: Colors.transparent),
        ),
      ]),
    );
  }
}

// ─── Painters ─────────────────────────────────────────────────────────────────
class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.07);
    const step = 24.0;
    for (double x = 0; x < size.width; x += step)
      for (double y = 0; y < size.height; y += step)
        canvas.drawCircle(Offset(x, y), 1, p);
  }
  @override bool shouldRepaint(_) => false;
}

class _ScanlinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = _cyan.withOpacity(0.012);
    for (double y = 0; y < size.height; y += 4)
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
  }
  @override bool shouldRepaint(_) => false;
}

// ─── Corp dots ────────────────────────────────────────────────────────────────
class _CorpDots extends StatelessWidget {
  final List<AnimationController> pulseControllers;
  const _CorpDots({required this.pulseControllers});

  @override
  Widget build(BuildContext context) {
    final items = [(_pink, 'Conecta'), (_green, 'Comunica'), (_orange, 'Colabora')];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: items.asMap().entries.map((e) {
        final i = e.key; final color = e.value.$1; final label = e.value.$2;
        return Padding(
          padding: EdgeInsets.only(left: i > 0 ? 20 : 0),
          child: Row(children: [
            ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 1.5).animate(
                CurvedAnimation(parent: pulseControllers[i], curve: Curves.easeInOut)),
              child: Container(width: 7, height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: color, blurRadius: 8)])),
            ),
            const SizedBox(width: 6),
            Text(label.toUpperCase(), style: GoogleFonts.spaceGrotesk(
              fontSize: 9, fontWeight: FontWeight.w500, letterSpacing: 1.5,
              color: Colors.white.withOpacity(0.4))),
          ]),
        );
      }).toList(),
    );
  }
}

// ─── Barra de progreso ────────────────────────────────────────────────────────
class _ProgressBar extends StatelessWidget {
  final double value;
  const _ProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).toInt();
    return SizedBox(
      width: 210,
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('INICIANDO SISTEMA', style: GoogleFonts.jetBrainsMono(
            fontSize: 9, letterSpacing: 1.8,
            color: Colors.white.withOpacity(0.25))),
          Text('$pct%', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: _cyan)),
        ]),
        const SizedBox(height: 6),
        Stack(clipBehavior: Clip.none, children: [
          Container(height: 1, width: 210, color: Colors.white.withOpacity(0.08)),
          Container(
            height: 1, width: 210 * value,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_blue, _cyan]),
              boxShadow: [BoxShadow(color: _cyan, blurRadius: 12)],
            ),
          ),
          if (value > 0.01)
            Positioned(
              left: (210 * value - 3.5).clamp(0.0, 210.0 - 7.0),
              top: -3,
              child: Container(width: 7, height: 7,
                decoration: const BoxDecoration(color: _cyan, shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: _cyan, blurRadius: 10),
                    BoxShadow(color: _cyan, blurRadius: 20),
                  ])),
            ),
        ]),
      ]),
    );
  }
}
