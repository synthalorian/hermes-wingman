import 'package:flutter/material.dart';
import 'package:hermes_wingman/theme/app_theme.dart';
import 'package:hermes_wingman/widgets/wingman_icon.dart';

class AnimatedWingmanMark extends StatelessWidget {
  final AppColorScheme scheme;
  final double size;
  const AnimatedWingmanMark({super.key, required this.scheme, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withAlpha(15),
            blurRadius: 4,
          ),
        ],
      ),
      child: WingmanIcon(size: size, showBackground: false),
    );
  }
}
