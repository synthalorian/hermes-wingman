import 'package:flutter/material.dart';

/// An animated launch splash screen worthy of Hermes.
/// Shows the caduceus-winged HW icon with a sweeping glow reveal.
class HermesSplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const HermesSplashScreen({super.key, required this.onComplete});

  @override
  State<HermesSplashScreen> createState() => _HermesSplashScreenState();
}

class _HermesSplashScreenState extends State<HermesSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<double> _glowRadius;
  late Animation<double> _taglineFade;
  late Animation<Offset> _taglineSlide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    // Logo: scale up from 0.6 → 1.0, fade in
    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack)),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.35, curve: Curves.easeOut)),
    );
    _glowRadius = Tween<double>(begin: 0.0, end: 40.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.2, 0.6, curve: Curves.easeOut)),
    );

    // Tagline: slides up and fades in
    _taglineFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 0.8, curve: Curves.easeOut)),
    );
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 12),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 0.8, curve: Curves.easeOutCubic),
    ));

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 400), widget.onComplete);
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF051412), // deep hermes teal
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [
                  Color(0xFF0A1F1C),
                  Color(0xFF051412),
                  Color(0xFF020A08),
                ],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 3),
                // Logo with glow
                Transform.scale(
                  scale: _logoScale.value,
                  child: Opacity(
                    opacity: _logoFade.value,
                    child: _SplashLogo(glowRadius: _glowRadius.value),
                  ),
                ),
                const SizedBox(height: 32),
                // Tagline
                SlideTransition(
                  position: _taglineSlide,
                  child: FadeTransition(
                    opacity: _taglineFade,
                    child: Column(
                      children: [
                        Text(
                          'HERMES WINGMAN',
                          style: TextStyle(
                            color: const Color(0xFFF5F0E8).withAlpha(230),
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 6,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'messenger of the grid',
                          style: TextStyle(
                            color: const Color(0xFF8BA888).withAlpha(180),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 3,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 4),
                // Subtle loading indicator
                SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: const Color(0xFF4A6B5D).withAlpha(120),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SplashLogo extends StatelessWidget {
  final double glowRadius;

  const _SplashLogo({required this.glowRadius});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: CustomPaint(
        painter: _SplashLogoPainter(glowRadius: glowRadius),
        size: const Size(96, 96),
      ),
    );
  }
}

class _SplashLogoPainter extends CustomPainter {
  final double glowRadius;

  _SplashLogoPainter({required this.glowRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final cx = s / 2;
    final cy = s / 2;

    if (glowRadius > 0) {
      // Outer glow
      final glowPaint = Paint()
        ..color = const Color(0xFF8BA888).withAlpha(20)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius);
      canvas.drawCircle(Offset(cx, cy), s * 0.35, glowPaint);

      // Inner ring glow
      final ringGlow = Paint()
        ..color = const Color(0xFFF5F0E8).withAlpha(10)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius * 0.6);
      canvas.drawCircle(Offset(cx, cy), s * 0.25, ringGlow);
    }

    // Orbital ring
    final ringPaint = Paint()
      ..color = const Color(0xFF8BA888).withAlpha(50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(Offset(cx, cy), s * 0.28, ringPaint);

    // Wings
    final wingColor = const Color(0xFFF5F0E8).withAlpha(200);
    final wingPaint = Paint()
      ..color = wingColor
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Left wing
    final lw = Path()
      ..moveTo(cx - s * 0.20, cy)
      ..quadraticBezierTo(cx - s * 0.32, cy - s * 0.18, cx - s * 0.36, cy - s * 0.30)
      ..quadraticBezierTo(cx - s * 0.28, cy - s * 0.18, cx - s * 0.24, cy - s * 0.08)
      ..quadraticBezierTo(cx - s * 0.28, cy - s * 0.14, cx - s * 0.26, cy - s * 0.22)
      ..quadraticBezierTo(cx - s * 0.23, cy - s * 0.12, cx - s * 0.20, cy - s * 0.06)
      ..quadraticBezierTo(cx - s * 0.21, cy - s * 0.10, cx - s * 0.20, cy - s * 0.13)
      ..quadraticBezierTo(cx - s * 0.18, cy - s * 0.08, cx - s * 0.16, cy - s * 0.06)
      ..quadraticBezierTo(cx - s * 0.17, cy - s * 0.10, cx - s * 0.18, cy - s * 0.14)
      ..lineTo(cx - s * 0.14, cy)
      ..close();
    canvas.drawPath(lw, wingPaint);

    // Right wing
    final rw = Path()
      ..moveTo(cx + s * 0.20, cy)
      ..quadraticBezierTo(cx + s * 0.32, cy - s * 0.18, cx + s * 0.36, cy - s * 0.30)
      ..quadraticBezierTo(cx + s * 0.28, cy - s * 0.18, cx + s * 0.24, cy - s * 0.08)
      ..quadraticBezierTo(cx + s * 0.28, cy - s * 0.14, cx + s * 0.26, cy - s * 0.22)
      ..quadraticBezierTo(cx + s * 0.23, cy - s * 0.12, cx + s * 0.20, cy - s * 0.06)
      ..quadraticBezierTo(cx + s * 0.21, cy - s * 0.10, cx + s * 0.20, cy - s * 0.13)
      ..quadraticBezierTo(cx + s * 0.18, cy - s * 0.08, cx + s * 0.16, cy - s * 0.06)
      ..quadraticBezierTo(cx + s * 0.17, cy - s * 0.10, cx + s * 0.18, cy - s * 0.14)
      ..lineTo(cx + s * 0.14, cy)
      ..close();
    canvas.drawPath(rw, wingPaint);

    // Central "H" — left vertical
    final hPaint = Paint()
      ..color = const Color(0xFFF5F0E8).withAlpha(230)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - s * 0.14, cy - s * 0.14, s * 0.04, s * 0.38),
        const Radius.circular(2),
      ),
      hPaint,
    );

    // "H" crossbar — gradient
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - s * 0.14, cy - s * 0.015, s * 0.28, s * 0.04),
        const Radius.circular(2),
      ),
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFFF5F0E8).withAlpha(230),
            const Color(0xFF8BA888).withAlpha(210),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(Rect.fromLTWH(cx - s * 0.14, cy - s * 0.015, s * 0.28, s * 0.04))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // "W" — right side
    final wPaint = Paint()
      ..color = const Color(0xFF8BA888).withAlpha(210)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.014
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final wPath = Path()
      ..moveTo(cx + s * 0.14, cy - s * 0.015)
      ..lineTo(cx + s * 0.18, cy + s * 0.17)
      ..lineTo(cx + s * 0.21, cy + s * 0.03)
      ..lineTo(cx + s * 0.24, cy + s * 0.17)
      ..lineTo(cx + s * 0.28, cy - s * 0.015);
    canvas.drawPath(wPath, wPaint);

    // Central star dot
    final dotPaint = Paint()..color = const Color(0xFFF5F0E8).withAlpha(240);
    final dotGlow = Paint()
      ..color = const Color(0xFF8BA888).withAlpha(80)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset(cx, cy - s * 0.04), s * 0.01, dotGlow);
    canvas.drawCircle(Offset(cx, cy - s * 0.04), s * 0.005, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _SplashLogoPainter oldDelegate) =>
      oldDelegate.glowRadius != glowRadius;
}