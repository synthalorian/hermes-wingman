import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hermes_wingman/theme/theme_manager.dart';
class ThemeSwitcherButton extends StatelessWidget {
  const ThemeSwitcherButton({super.key});

  @override
  Widget build(BuildContext context) {
    final themeManager = context.watch<ThemeManager>();
    final scheme = themeManager.currentScheme;

    return PopupMenuButton<String>(
      tooltip: 'Switch Theme',
      offset: const Offset(0, -40),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.borderDim.withAlpha(60), width: 0.5),
      ),
      color: scheme.surface.withAlpha(230),
      onSelected: (name) => themeManager.setTheme(name),
      itemBuilder: (context) => themeManager.availableThemes.map((name) {
        final current = name == themeManager.currentThemeName;
        return PopupMenuItem<String>(
          value: name,
          child: Row(
            children: [
              Icon(current ? Icons.brightness_1 : Icons.circle_outlined, size: 10,
                color: current ? scheme.primary : scheme.textMuted),
              const SizedBox(width: 10),
              Text(name, style: TextStyle(
                color: current ? scheme.primary : scheme.text,
                fontWeight: current ? FontWeight.w600 : FontWeight.w400)),
              if (current) ...[const Spacer(), Icon(Icons.check, size: 14, color: scheme.primary)],
            ],
          ),
        );
      }).toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Container(
          width: 52, height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.borderDim.withAlpha(40), width: 0.5),
          ),
          child: Icon(Icons.palette_outlined, size: 18, color: scheme.textMuted),
        ),
      ),
    );
  }
}
