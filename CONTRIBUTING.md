# Contributing to Hermes Wingman

First off, thanks for wanting to contribute. Hermes Wingman is built for the Hermes community — your input makes it better.

## 🧭 Project Overview

Hermes Wingman is a **single monorepo with three editions** that replace the Hermes CLI entirely:

| Platform | Stack | Location |
|----------|-------|----------|
| **Desktop App** | Flutter + Rust backend | `lib/`, `backend/` |
| **Mobile App** | Flutter (Android/iOS) | Same codebase as desktop |
| **Web Dashboard** | Ruby on Rails 8 + Tailwind | `web/` |

All three platforms share the same **Rust backend** (port 9120) and the same **29-theme CSS/Flutter design system** — now in one repository.

## 🔧 Development Setup

### Full Stack

```bash
# Clone
git clone https://github.com/synthalorian/hermes-wingman.git
cd hermes-wingman

# Flutter dependencies
flutter pub get

# Rust backend
cd backend && cargo build --release && cd ..

# Rails web app
cd web
bundle install
bin/rails tailwindcss:build
```

### Running in Development

```bash
# Terminal 1: Rust backend (bind to all interfaces for mobile testing)
cd hermes_wingman
BIND_ADDR=0.0.0.0:9120 backend/target/release/hermes-wingman-backend

# Terminal 2: Flutter desktop
cd hermes_wingman
flutter run -d linux

# Terminal 3: Rails web app
cd hermes-wingman/web
bin/rails tailwindcss:build
bin/rails server -b 0.0.0.0 -p 3000
```

## 🏗 Architecture

### Flutter App (`hermes_wingman/lib/`)

- **`main.dart`** — App entry point with Hermes splash screen, animated starfield, glass sidebar
- **`theme/`** — 29-theme CSS system, glass card widgets, page transitions
- **`screens/`** — 15 screens, each in its own folder (dashboard, chat, models, config, etc.)
- **`services/`** — BackendService (HTTP to Rust), HermesClient (CLI fallback), ChatManager
- **`models/`** — Plain Dart classes with factory constructors for Hermes data types

**Key pattern:** Every screen uses `context.watch<ThemeManager>().currentScheme` for theme colors. Every widget accepts `AppColorScheme scheme` as a parameter.

### Rust Backend (`hermes_wingman/backend/src/`)

A modular Axum HTTP server (24 files) with 40+ API endpoints spread across 12 handler modules. Handles:
- Direct API calls to providers (OpenAI, Anthropic, llama-swap, etc.)
- Hermes CLI fallback for OAuth providers
- File system operations, config management
- Session management, cron parsing

### Rails Web App (`web/`)

- 24 controllers mapping to Flutter screens
- All requests proxy through the Rust backend via `HermesApiService`
- 29-theme CSS custom property system matching Flutter exactly
- SQLite for local metadata (profiles, missions, webhooks)

## 🎨 Adding a Theme

Themes must be defined in **three places** to maintain parity across platforms:

1. **Flutter:** Add a const `AppColorScheme` in `lib/theme/app_theme.dart`, register in `allThemes` and `themeNames`
2. **Rails:** Add a `[data-theme="name"]` CSS block in `app/assets/tailwind/application.css` with matching hex values
3. **Rails picker:** Add the theme to the theme picker dialog in `app/views/layouts/application.html.erb`
4. **Rails controller:** Add the name to `ThemeController::VALID_THEMES`

The **Hermes theme** is the default flagship — it should always be the most polished.

## 📐 Code Style (Flutter)

- **Import order:** Flutter → packages → `../../` relative imports
- **State:** Use `StatefulWidget` with local state (no global state except theme)
- **Error handling:** Every screen handles loading / error / empty / data states
- **Theme-aware:** Every widget accepts `scheme` (AppColorScheme) as a parameter
- **BackdropFilter + Material:** Every `BackdropFilter` must wrap its child in `Material(type: MaterialType.transparency)` to avoid InkWell/Material ancestor errors
- **Provider pattern:** Use `Provider.debugCheckInvalidValueType = null` in `main()` when providing Listenable subtypes under a non-Listenable interface type

## 📐 Code Style (Rails)

- **Controllers:** RESTful, one per feature, use `HermesApiService` for backend calls
- **Views:** Use Tailwind utility classes + CSS custom properties for theming
- **No inline JS for theming:** Theme switching is a form POST → session cookie → CSS `[data-theme]` attribute
- **Prefer Hotwire/Turbo** over custom JavaScript for dynamic updates

## 🐛 Reporting Issues

Open a GitHub issue with:
- What you expected to happen
- What actually happened
- Which platform (desktop/mobile/web)
- Your OS and Hermes version (`hermes --version`)
- Any relevant log output or error messages

## 🚀 Pull Requests

1. Small PRs are better than big ones — one feature or fix per PR
2. Keep `dart analyze` clean (zero errors)
3. Keep `flutter build` and `cargo build` passing
4. Update appropriate READMEs when adding features
5. Screenshots help for UI changes
6. For theme changes, confirm parity across all three platforms

## 📝 License

By contributing, you agree that your contributions will be licensed under the MIT License.