<p align="center">
  <img src="assets/icons/hermes-wingman.png" width="256" height="256" alt="Hermes Wingman">
</p>

<h1 align="center">Hermes Wingman</h1>

<p align="center">
  <strong>The definitive GUI for <a href="https://hermes-agent.nousresearch.com">Hermes Agent</a></strong>
  <br>
  Cross-platform desktop &amp; mobile frontend for your AI agent
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows%20|%20Android%20|%20iOS-blue" alt="Platforms">
  <img src="https://img.shields.io/badge/frontend-Flutter-02569B" alt="Flutter">
  <img src="https://img.shields.io/badge/backend-Rust-orange" alt="Rust">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/version-0.1.0-red" alt="Version">
</p>

---

## 📋 Overview

Hermes Wingman is a **cross-platform GUI** for [Hermes Agent](https://hermes-agent.nousresearch.com) — the open-source AI agent by Nous Research. It provides a beautiful, synthwave-inspired interface to chat, configure, monitor, and control your Hermes agent from any device on your network.

**Desktop mode:** Sidebar navigation with system tray integration.
**Mobile mode:** Bottom navigation bar, connects to a remote Hermes Wingman backend on your desktop/server.

### Key Features

- 💬 **Chat with Hermes** — tabbed conversations with streaming responses, session history, and SOUL.md identity injection
- 🔄 **Model switching** — switch between llama-swap local models and cloud providers without touching config files
- 📋 **Session management** — view, search, resume, and export past Hermes sessions
- ⚙️ **Config editor** — full YAML editor with syntax highlighting for `config.yaml`
- 📊 **Dashboard** — real-time status for sessions, cron jobs, gateways, and the active model
- 📝 **Live logs** — view Hermes agent logs with level filtering
- ⏰ **Cron jobs** — manage scheduled agent tasks
- 🌐 **Gateway control** — monitor and toggle Discord, Telegram, and other platform bridges
- 🎨 **Synthwave themes** — multiple dark and light color schemes with a neon 80s aesthetic
- 🔌 **Remote access** — mobile app connects to the backend over your LAN

---

## 🏗️ Architecture

```
┌─────────────────────┐     HTTP API      ┌─────────────────────────────┐
│  Flutter Frontend   │ ◄──────────────►   │  Rust Backend               │
│                     │      port 9120     │  (actix-web HTTP server)    │
│  - Desktop: sidebar │                    │                              │
│  - Mobile: bottom   │                    │  - Chat streaming (SSE)     │
│    navigation       │                    │  - Model probing            │
│                     │                    │  - Session management       │
│  Platforms:         │                    │  - Config management        │
│  Linux / macOS      │                    │  - OAuth-aware routing      │
│  Windows / Android  │                    │  - Hermes CLI fallback      │
│  iOS                │                    │                              │
└─────────────────────┘                    └─────────────────────────────┘
                                                    │
                                                    ▼
                                         ┌─────────────────────┐
                                         │  Hermes Agent CLI   │
                                         │  (OAuth token mgmt) │
                                         └─────────────────────┘
```

### How It Works

1. **Rust Backend** runs on a desktop/server and exposes a REST API on port 9120
2. **Flutter Frontend** connects to the backend via HTTP — locally on desktop, or over LAN on mobile
3. The backend can make **direct API calls** to providers (llama-swap, OpenAI, Anthropic, etc.) or **shell out to the Hermes CLI** for OAuth-based providers (Nous Free Tier, xAI)
4. For **OAuth providers**, the backend automatically detects the OAuth tokens in `~/.hermes/auth.json` and routes through the Hermes CLI — no token refresh issues

---

## 🚀 Getting Started

### Prerequisites

- **Hermes Agent** installed and configured ([install guide](https://hermes-agent.nousresearch.com))
- For local models: **llama-swap** running on port 8080

### Quick Start (Desktop)

**Download the latest release** from the [Releases page](https://github.com/synthalorian/hermes-wingman/releases):

| Platform | Format |
|----------|--------|
| Linux | `hermes-wingman-linux.tar.gz` (extract and run `./hermes_wingman`) |
| Windows | `hermes-wingman-windows.zip` |
| macOS | `hermes-wingman-macos.dmg` |

The app auto-detects your Hermes installation and starts the backend automatically.

### Building from Source

#### Flutter Setup

```bash
# Clone the repo
git clone https://github.com/synthalorian/hermes-wingman.git
cd hermes-wingman

# Build the Rust backend
cd backend
cargo build --release
cd ..

# Build the Flutter app for your platform
flutter build linux --release     # Linux
flutter build macos --release     # macOS
flutter build windows --release   # Windows
flutter build apk --release       # Android
flutter build ios --release       # iOS (requires macOS + Xcode)
```

#### Android Build Notes

The Android build requires JDK 21+. If you're on a newer JDK, set `JAVA_HOME`:

```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
flutter build apk --release
```

#### iOS Build Notes

iOS builds require:
- macOS with Xcode 16+
- An Apple Developer account (for device deployment)
- CocoaPods installed (`sudo gem install cocoapods`)

```bash
cd ios && pod install && cd ..
flutter build ios --release
```

### Running on Mobile

1. Start the backend on your desktop: `~/.local/bin/hermes-wingman-backend`
2. Open Hermes Wingman on your phone
3. Go to **Settings** → tap **Change** next to the backend URL
4. Enter your desktop's LAN IP (e.g., `192.168.1.100`) and port `9120`
5. Tap **Connect**

All features work remotely — chat, sessions, config editing, everything.

---

## 📱 Mobile App

The mobile app provides the same functionality as the desktop version, adapted for touch:

- **Bottom navigation** with Dashboard, Chat, Models, Sessions, and Settings tabs
- **SSE streaming chat** with the same SOUL.md identity injection
- **Connection management** — change backend IP/port from Settings
- **Full session browsing** and model switching
- **Config editing** with syntax-highlighted YAML view

Download the APK from the [Releases page](https://github.com/synthalorian/hermes-wingman/releases).

---

## 🖥️ Desktop App

The desktop app uses a **sidebar navigation** with system tray integration:

- **System tray** — minimize to tray, quick access from the notification area
- **10 navigation tabs** — Dashboard, Chat, Models, Tools, Sessions, Config, Logs, Cron, Gateway, Setup Wizard
- **Full keyboard support** — tab through everything
- **Dark and light themes** with synthwave aesthetic

---

## 🎨 Themes

Hermes Wingman ships with multiple synthwave-inspired themes:

- **Synthwave** — neon cyan on deep blue-black
- **Blood & Chrome** — crimson and silver
- **Vaporwave** — pastel pink and purple
- **Midnight** — deep indigo
- **Crystal** — light, clean design
- **Amber** — warm orange CRT glow

Switch themes anytime from the palette icon in the bottom-left sidebar (desktop).

---

## 🔧 Configuration

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `OPENAI_API_KEY` | OpenAI provider |
| `ANTHROPIC_API_KEY` | Anthropic provider |
| `DEEPSEEK_API_KEY` | DeepSeek/Nous API key (legacy) |
| `OPENROUTER_API_KEY` | OpenRouter provider |

### Backend Port

The backend runs on port **9120** by default. To change it, either:
- Edit the port in `backend/src/main.rs` and rebuild
- Or use a reverse proxy (nginx, Caddy) to forward to 9120

---

## 🤝 Contributing

Hermes Wingman is open source and welcomes contributions!

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing`)
5. Open a Pull Request

### Development Setup

```bash
# Clone
git clone https://github.com/synthalorian/hermes-wingman.git
cd hermes-wingman

# Run Flutter in debug mode (connects to existing backend)
flutter run

# Or run both backend + frontend
cd backend && cargo run --release &
cd .. && flutter run
```

---

## ☕ Support Development

If Hermes Wingman helps you work faster, smoother, or cooler — consider buying me a coffee!

<p align="center">
  <a href="https://buymeacoffee.com/synthalorian">
    <img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&emoji=☕&slug=synthalorian&button_colour=5F7FFF&font_colour=ffffff&font_family=Cookie&outline_colour=000000&coffee_colour=FFDD00" alt="Buy Me a Coffee">
  </a>
</p>

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

Built with ❤️ by [synthalorian](https://github.com/synthalorian)
