import 'dart:math';
import 'package:flutter/material.dart';

/// A subtle animated starfield + constellation particle system.
/// Renders behind all UI to give depth and motion worthy of a god.
class AnimatedBackground extends StatefulWidget {
  final Color primaryColor;
  final Color accentColor;
  final Color baseColor;

  const AnimatedBackground({
    super.key,
    required this.primaryColor,
    required this.accentColor,
    required this.baseColor,
  });

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Star> _stars = [];
  final List<_Constellation> _constellations = [];
  final Random _rng = Random(42); // seeded for stable layout

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();

    // Generate stars (count scales with pixel density)
    for (int i = 0; i < 80; i++) {
      _stars.add(_Star(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        size: 0.5 + _rng.nextDouble() * 1.5,
        opacity: 0.2 + _rng.nextDouble() * 0.5,
        twinkleSpeed: 1.0 + _rng.nextDouble() * 3.0,
        phase: _rng.nextDouble() * 2 * pi,
      ));
    }

    // Generate constellation lines (subtle)
    for (int i = 0; i < 2; i++) {
      final starCount = 3 + _rng.nextInt(4);
      final indices = <int>{};
      while (indices.length < starCount) {
        indices.add(_rng.nextInt(_stars.length));
      }
      final idxList = indices.toList();
      for (int j = 0; j < idxList.length - 1; j++) {
        _constellations.add(_Constellation(
          fromIdx: idxList[j],
          toIdx: idxList[j + 1],
          opacity: 0.04 + _rng.nextDouble() * 0.06,
        ));
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _StarfieldPainter(
            stars: _stars,
            constellations: _constellations,
            primaryColor: widget.primaryColor,
            accentColor: widget.accentColor,
            baseColor: widget.baseColor,
            time: _controller.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _Star {
  final double x, y, size, opacity, twinkleSpeed, phase;
  const _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.opacity,
    required this.twinkleSpeed,
    required this.phase,
  });
}

class _Constellation {
  final int fromIdx, toIdx;
  final double opacity;
  const _Constellation({
    required this.fromIdx,
    required this.toIdx,
    required this.opacity,
  });
}

class _StarfieldPainter extends CustomPainter {
  final List<_Star> stars;
  final List<_Constellation> constellations;
  final Color primaryColor;
  final Color accentColor;
  final Color baseColor;
  final double time;

  _StarfieldPainter({
    required this.stars,
    required this.constellations,
    required this.primaryColor,
    required this.accentColor,
    required this.baseColor,
    required this.time,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Constellation lines
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.3;
    for (final c in constellations) {
      final from = stars[c.fromIdx];
      final to = stars[c.toIdx];
      final twinkle = sin(time * c.fromIdx * 2 + c.fromIdx) * 0.5 + 0.5;
      final opacity = c.opacity * (0.3 + twinkle * 0.7);
      final alpha = (opacity * 255).round().clamp(2, 25);
      linePaint.color = accentColor.withAlpha(alpha);
      canvas.drawLine(
        Offset(from.x * size.width, from.y * size.height),
        Offset(to.x * size.width, to.y * size.height),
        linePaint,
      );
    }

    // Stars
    for (final star in stars) {
      final twinkle = sin(time * star.twinkleSpeed + star.phase) * 0.5 + 0.5;
      final alpha = (star.opacity * (0.4 + twinkle * 0.6) * 255).clamp(8, 200).toInt();
      final x = star.x * size.width;
      final y = star.y * size.height;

      final starPaint = Paint()..color = primaryColor.withAlpha(alpha);
      canvas.drawCircle(Offset(x, y), star.size, starPaint);

      // Subtle glow on brighter stars
      if (star.size > 1.2) {
        final glowPaint = Paint()
          ..color = accentColor.withAlpha((alpha * 0.15).toInt().clamp(2, 30))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawCircle(Offset(x, y), star.size * 2.5, glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter oldDelegate) =>
      oldDelegate.time != time;
}