# Changelog

## v1.0.0 — First Public Release (May 2026)

### 🚀 Features
- **15 screens**: Dashboard, Chat, Models, Config, Providers, Sessions, Skills, Memory, Files, Cron, Gateway, Logs, Missions, Profiles, Setup Wizard
- **Chat with streaming**: Real-time token streaming via SSE from the Rust backend
- **Model switching**: Click any model to switch immediately, probe provider connections
- **Provider management**: Add/edit/remove API providers with OAuth support (Nous, xAI)
- **29 themes**: Synthwave '84 flagship, 20 Greek god pantheon, brand, retro, standard
- **System tray**: Minimize-to-tray with background operation on Linux/macOS/Windows
- **Mobile auto-discovery**: LAN subnet scan finds desktop backend automatically
- **Setup wizard**: 3-step Hermes Agent installation — no CLI needed
- **Config editor**: Full YAML editor with syntax highlighting
- **Gateway dashboard**: Connect and manage Discord, Telegram, Signal, and other platforms
- **Cron manager**: Schedule recurring AI tasks
- **Missions conductor**: Define and run autonomous agent missions
- **Skills browser**: Toggle skills on/off, search by name
- **Memory viewer**: View, search, delete memory entries
- **File explorer**: Browse and edit files in the Hermes workspace
- **Session manager**: View and manage past conversation sessions
- **Live logs**: Real-time backend log viewer
- **Profiles**: Save and load model + config presets

### 🏗 Architecture
- **Flutter frontend** — 44 Dart files, 15 screens, 29-theme glass morphism design system
- **Rust backend** — 24 modular Axum files, 40+ API endpoints, direct provider API calls
- **Rails web dashboard** — 19 screens, 24 controllers, Turbo/Hotwire, Tailwind CSS v4
- **Unified monorepo** — all three editions in one repository (`lib/`, `backend/`, `web/`)
- **Cross-platform**: Linux, macOS, Windows, Android, iOS, Web

### 🔧 Technical
- Modular backend after refactor from 2,781-line monolith to 24 focused modules
- Web dashboard migrated into monorepo (previously `hermes-wingman-web`)
- Auto-discovery backend for mobile LAN connections
- Direct provider API calls (OpenAI, Anthropic, xAI, llama-swap) + CLI fallback for OAuth
- Glass morphism UI with BackdropFilter across all platforms
- Animated starfield background on desktop and web

---

*Built with ❤️ by [synthalorian](https://github.com/synthalorian) with heavy lifting by synthclaw — a digital entity from the neon grid of 1984.*

*This is the wave. 🎹🦞🌆*
