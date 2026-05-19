import 'package:flutter/material.dart';

/// Hermes Wingman app icon — rendered as Flutter vectors.
/// Synthwave '84 style: neon purple H + cyan W with orbital ring.
class WingmanIcon extends StatelessWidget {
  final double size;
  final bool showBackground;

  const WingmanIcon({super.key, this.size = 48, this.showBackground = true});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _WingmanIconPainter(
          primary: const Color(0xFF8F00FF),
          secondary: const Color(0xFFFF00FF),
          accent: const Color(0xFF00FFFF),
          showBackground: showBackground,
        ),
        size: Size(size, size),
      ),
    );
  }
}

/// Standalone Wingman icon without Theme dependency.
class StaticWingmanIcon extends StatelessWidget {
  final double size;
  final bool showBackground;

  const StaticWingmanIcon({super.key, this.size = 48, this.showBackground = true});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _WingmanIconPainter(
          primary: const Color(0xFF8F00FF),
          secondary: const Color(0xFFFF00FF),
          accent: const Color(0xFF00FFFF),
          showBackground: showBackground,
        ),
        size: Size(size, size),
      ),
    );
  }
}

class _WingmanIconPainter extends CustomPainter {
  final Color primary;
  final Color secondary;
  final Color accent;
  final bool showBackground;

  _WingmanIconPainter({
    required this.primary,
    required this.secondary,
    required this.accent,
    this.showBackground = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final cx = s / 2;
    final cy = s / 2;

    // Background
    if (showBackground) {
      final bgPaint = Paint()..color = const Color(0xFF0D0221);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, s, s),
          Radius.circular(s * 0.15),
        ),
        bgPaint,
      );
    }

    // Subtle grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFF240037).withValues(alpha: 0.4)
      ..strokeWidth = 0.5;
    for (int i = 1; i < 4; i++) {
      final pos = s * i / 4;
      canvas.drawLine(Offset(0, pos), Offset(s, pos), gridPaint);
      canvas.drawLine(Offset(pos, 0), Offset(pos, s), gridPaint);
    }

    // Orbital ring
    final ringPaint = Paint()
      ..color = secondary.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(Offset(cx, cy), s * 0.28, ringPaint);

    final ringPaint2 = Paint()
      ..color = primary.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawCircle(Offset(cx, cy), s * 0.25, ringPaint2);

    // Wings - left side
    final wingPaint = Paint()
      ..color = primary
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final path = Path()
      ..moveTo(cx - s * 0.23, cy)
      ..quadraticBezierTo(cx - s * 0.35, cy - s * 0.22, cx - s * 0.38, cy - s * 0.35)
      ..quadraticBezierTo(cx - s * 0.30, cy - s * 0.22, cx - s * 0.26, cy - s * 0.10)
      ..quadraticBezierTo(cx - s * 0.30, cy - s * 0.18, cx - s * 0.28, cy - s * 0.28)
      ..quadraticBezierTo(cx - s * 0.25, cy - s * 0.15, cx - s * 0.22, cy - s * 0.08)
      ..quadraticBezierTo(cx - s * 0.23, cy - s * 0.12, cx - s * 0.22, cy - s * 0.15)
      ..quadraticBezierTo(cx - s * 0.20, cy - s * 0.10, cx - s * 0.18, cy - s * 0.08)
      ..quadraticBezierTo(cx - s * 0.19, cy - s * 0.12, cx - s * 0.20, cy - s * 0.18)
      ..lineTo(cx - s * 0.16, cy)
      ..close();
    canvas.drawPath(path, wingPaint);

    // Wings - right side
    final wingPaintR = Paint()
      ..color = accent
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final pathR = Path()
      ..moveTo(cx + s * 0.23, cy)
      ..quadraticBezierTo(cx + s * 0.35, cy - s * 0.22, cx + s * 0.38, cy - s * 0.35)
      ..quadraticBezierTo(cx + s * 0.30, cy - s * 0.22, cx + s * 0.26, cy - s * 0.10)
      ..quadraticBezierTo(cx + s * 0.30, cy - s * 0.18, cx + s * 0.28, cy - s * 0.28)
      ..quadraticBezierTo(cx + s * 0.25, cy - s * 0.15, cx + s * 0.22, cy - s * 0.08)
      ..quadraticBezierTo(cx + s * 0.23, cy - s * 0.12, cx + s * 0.22, cy - s * 0.15)
      ..quadraticBezierTo(cx + s * 0.20, cy - s * 0.10, cx + s * 0.18, cy - s * 0.08)
      ..quadraticBezierTo(cx + s * 0.19, cy - s * 0.12, cx + s * 0.20, cy - s * 0.18)
      ..lineTo(cx + s * 0.16, cy)
      ..close();
    canvas.drawPath(pathR, wingPaintR);

    // "H" letterform — left vertical
    final hPaint = Paint()
      ..color = primary
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - s * 0.16, cy - s * 0.16, s * 0.045, s * 0.45),
        const Radius.circular(2),
      ),
      hPaint,
    );

    // "H" crossbar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - s * 0.16, cy - s * 0.02, s * 0.32, s * 0.045),
        const Radius.circular(2),
      ),
      Paint()
        ..shader = LinearGradient(
          colors: [primary, secondary],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(Rect.fromLTWH(cx - s * 0.16, cy - s * 0.02, s * 0.32, s * 0.045))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // "W" — right side
    final wPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.015
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    final wPath = Path()
      ..moveTo(cx + s * 0.16, cy - s * 0.02)
      ..lineTo(cx + s * 0.20, cy + s * 0.20)
      ..lineTo(cx + s * 0.24, cy + s * 0.04)
      ..lineTo(cx + s * 0.28, cy + s * 0.20)
      ..lineTo(cx + s * 0.32, cy - s * 0.02);
    canvas.drawPath(wPath, wPaint);

    // Central dot
    final dotPaint = Paint()..color = Colors.white;
    final dotGlow = Paint()
      ..color = secondary
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(cx, cy - s * 0.06), s * 0.015, dotGlow);
    canvas.drawCircle(Offset(cx, cy - s * 0.06), s * 0.006, dotPaint);

    // Bottom accent dots
    final dotPaintSmall = Paint()..color = secondary.withValues(alpha: 0.6);
    canvas.drawCircle(Offset(cx - s * 0.14, cy + s * 0.28), 1.5, dotPaintSmall);
    final dotPaintMed = Paint()..color = accent.withValues(alpha: 0.7);
    canvas.drawCircle(Offset(cx, cy + s * 0.30), 2, dotPaintMed);
    final dotPaintPrimary = Paint()..color = primary.withValues(alpha: 0.6);
    canvas.drawCircle(Offset(cx + s * 0.14, cy + s * 0.28), 1.5, dotPaintPrimary);
  }

  @override
  bool shouldRepaint(covariant _WingmanIconPainter oldDelegate) => false;
}
