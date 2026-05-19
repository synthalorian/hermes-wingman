# Contributing to Hermes Wingman

First off, thanks for wanting to contribute. Hermes Wingman is built for the Hermes community — your input makes it better.

## 🧭 Project Overview

Hermes Wingman is a Flutter desktop app that wraps the Hermes Agent CLI. The heavy lifting is done by `hermes_client.dart` which talks to the local `hermes` binary. The UI is a thin layer on top — mostly list views, status indicators, and theme styling.

## 🔧 Setup

```bash
git clone https://github.com/synthalorian/hermes-wingman
cd hermes-wingman
flutter pub get
dart analyze  # Should be clean
flutter build linux --debug  # Or macos/windows
```

## 🏗 Architecture

Three layers:

1. **HermesClient** (`lib/services/hermes_client.dart`) — the only file that calls the `hermes` CLI or reads files. If you're adding a feature that needs new Hermes data, add a method here first.

2. **Models** (`lib/models/hermes_models.dart`) — plain Dart classes with factory constructors. Keep them simple, no business logic.

3. **Screens** (`lib/screens/*/`) — one folder per screen. Each screen is self-contained with its own state, error handling, and loading states.

Themes are in `lib/theme/app_theme.dart`. Add a new theme by adding a const `AppColorScheme` and registering it in `allThemes` and `themeNames`.

## 📐 Code Style

- **Import order:** Flutter → packages → `../../` relative imports
- **State:** Use `StatefulWidget` with local state (no global state unless it's a theme)
- **Error handling:** Every screen handles loading / error / empty / data states
- **No magic numbers:** Color values, padding, and sizing should be derived from `AppColorScheme`
- **Theme-aware:** Every widget accepts `scheme` (AppColorScheme) as a parameter

## 🎨 Adding a Theme

1. Add a const `AppColorScheme` in `lib/theme/app_theme.dart`
2. Add it to `allThemes` map
3. Add the name to `themeNames` list
4. If it's a dark theme, add it to the `isDark` check in `themeDataFromScheme()`

Theme naming convention: `snake_case` for the const, human-readable for the display name.

## 🐛 Reporting Issues

Open a GitHub issue with:
- What you expected to happen
- What actually happened
- Your OS and Hermes version (`hermes --version`)
- Any relevant log output

## 🚀 Pull Requests

1. Small PRs are better than big ones — one feature or fix per PR
2. Keep `dart analyze` clean (zero issues)
3. Keep `flutter build` passing
4. Update README if adding visible features
5. Screenshots help for UI changes

## 📝 License

By contributing, you agree that your contributions will be licensed under the MIT License.
