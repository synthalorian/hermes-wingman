import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Provider-based theme manager.
/// Wraps theme selection and persists the choice.
class ThemeManager extends ChangeNotifier {
  String _currentThemeName = 'Synthwave \'84';
  late AppColorScheme _currentScheme;

  ThemeManager() {
    _currentScheme = allThemes[_currentThemeName]!;
  }

  String get currentThemeName => _currentThemeName;
  AppColorScheme get currentScheme => _currentScheme;
  ThemeData get themeData => themeDataFromScheme(_currentScheme);

  List<String> get availableThemes => themeNames;

  void setTheme(String name) {
    if (allThemes.containsKey(name) && name != _currentThemeName) {
      _currentThemeName = name;
      _currentScheme = allThemes[name]!;
      notifyListeners();
    }
  }
}
