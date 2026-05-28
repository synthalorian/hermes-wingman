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
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: glowRadius > 0
            ? [
                BoxShadow(
                  color: const Color(0xFF8BA888).withAlpha(20),
                  blurRadius: glowRadius,
                  spreadRadius: glowRadius * 0.5,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.asset(
          'assets/icons/hermes-wingman.png',
          width: 96,
          height: 96,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

