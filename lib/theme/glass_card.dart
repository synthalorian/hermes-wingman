import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// A frosted glass card with backdrop blur, subtle border, and optional glow.
class GlassCard extends StatelessWidget {
  final Widget child;
  final AppColorScheme scheme;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final double blurSigma;
  final double borderRadius;
  final Color? tintColor;
  final Color? borderColor;
  final Color? glowColor;
  final double glowRadius;
  final List<BoxShadow>? extraShadows;
  final EdgeInsetsGeometry? margin;

  const GlassCard({
    super.key,
    required this.child,
    required this.scheme,
    this.padding,
    this.width,
    this.height,
    this.blurSigma = 12,
    this.borderRadius = 10,
    this.tintColor,
    this.borderColor,
    this.glowColor,
    this.glowRadius = 0,
    this.extraShadows,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveTint = tintColor ?? scheme.surface.withAlpha(160);
    final effectiveBorder = borderColor ?? scheme.borderDim.withAlpha(60);
    final effectiveGlow = glowColor ?? scheme.primary;

    final boxShadow = <BoxShadow>[];
    if (glowRadius > 0) {
      boxShadow.add(BoxShadow(
        color: effectiveGlow.withAlpha(30),
        blurRadius: glowRadius,
        spreadRadius: 1,
      ));
    }
    if (extraShadows != null) {
      boxShadow.addAll(extraShadows!);
    }

    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding ?? const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: effectiveTint,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: effectiveBorder, width: 0.5),
              boxShadow: boxShadow.isNotEmpty ? boxShadow : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A glow shadow helper — produce a list of BoxShadow with the theme's colors.
List<BoxShadow> glowShadow(AppColorScheme scheme, {double radius = 8, double opacity = 0.12}) {
  return [
    BoxShadow(
      color: scheme.primary.withAlpha((opacity * 255).round()),
      blurRadius: radius,
      spreadRadius: 0.5,
    ),
    BoxShadow(
      color: scheme.accent.withAlpha((opacity * 128).round()),
      blurRadius: radius * 1.5,
      spreadRadius: 0,
    ),
  ];
}

/// A subtle bottom-edge glow divider line.
class GlowDivider extends StatelessWidget {
  final AppColorScheme scheme;
  final double height;
  final EdgeInsetsGeometry? margin;

  const GlowDivider({
    super.key,
    required this.scheme,
    this.height = 0.5,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: margin ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withAlpha(0),
            scheme.primary.withAlpha(60),
            scheme.accent.withAlpha(30),
            scheme.primary.withAlpha(0),
          ],
          stops: const [0.0, 0.3, 0.7, 1.0],
        ),
      ),
    );
  }
}

/// Apply glow box-decoration to any Container
Decoration glassDecoration(AppColorScheme scheme,
    {double borderRadius = 10, double glowOpacity = 0.0}) {
  return BoxDecoration(
    color: scheme.surface.withAlpha(200),
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(color: scheme.borderDim.withAlpha(50), width: 0.5),
    boxShadow: glowOpacity > 0
        ? [
            BoxShadow(
              color: scheme.primary.withAlpha((glowOpacity * 255 * 0.5).round()),
              blurRadius: 12,
              spreadRadius: 0.5,
            ),
          ]
        : null,
  );
}

/// A stat card wrapper that adds the glass aesthetic with a glowing accent top edge.
class AccentGlassCard extends StatelessWidget {
  final Widget child;
  final AppColorScheme scheme;
  final Color accentColor;
  final EdgeInsetsGeometry? padding;
  final double? width;

  const AccentGlassCard({
    super.key,
    required this.child,
    required this.scheme,
    required this.accentColor,
    this.padding,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: padding ?? const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surface.withAlpha(180),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.borderDim.withAlpha(50), width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withAlpha(25),
                  blurRadius: 12,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border(
                top: BorderSide(color: accentColor.withAlpha(80), width: 1.0),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
