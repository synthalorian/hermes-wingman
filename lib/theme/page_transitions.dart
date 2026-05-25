import 'package:flutter/material.dart';

/// Hermes-style page transitions — swift, smooth, godly.
/// Used in main.dart for all screen swaps.

class HermesPageTransition extends StatelessWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  const HermesPageTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.06, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      )),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Use this as pageTransitionsTheme in your ThemeData.
final hermeticTransitions = const PageTransitionsTheme(
  builders: {
    TargetPlatform.android: HermesTransitionBuilder(),
    TargetPlatform.iOS: HermesTransitionBuilder(),
    TargetPlatform.linux: HermesTransitionBuilder(),
    TargetPlatform.macOS: HermesTransitionBuilder(),
    TargetPlatform.windows: HermesTransitionBuilder(),
  },
);

class HermesTransitionBuilder extends PageTransitionsBuilder {
  const HermesTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return HermesPageTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

/// Fade + scale transition for dialogs and modals.
class HermesDialogTransition extends StatelessWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  const HermesDialogTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.92, end: 1.0).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
      ),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOut),
        ),
        child: child,
      ),
    );
  }
}