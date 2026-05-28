import 'package:flutter/material.dart';
import 'package:hermes_wingman/theme/app_theme.dart';

class SidebarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String badge;
  final bool selected;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const SidebarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.badge,
    required this.selected,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
        child: Material(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Container(
              width: 52, height: 48,
              padding: const EdgeInsets.only(left: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: selected ? Border(left: BorderSide(color: color, width: 2)) : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(height: 2),
                  Text(
                    badge,
                    style: TextStyle(
                      fontSize: 8, color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
