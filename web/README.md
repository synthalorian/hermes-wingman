# Hermes Wingman — Web Dashboard

The browser-based edition of [Hermes Wingman](https://github.com/synthalorian/hermes-wingman) — part of the unified monorepo.

## Stack

- **Ruby on Rails 8.1** with Hotwire/Turbo for SPA-like navigation
- **Tailwind CSS v4** with 29-theme CSS custom property system
- **SQLite** for local metadata (profiles, missions, webhooks, etc.)
- Proxies to the **Rust backend** (`../backend/`, port 9120) for all Hermes operations

## Quick Start

```bash
cd web

# Install dependencies
bundle install

# Build Tailwind CSS
bin/rails tailwindcss:build

# Start the server (ensure Rust backend is running on port 9120)
bin/rails server -b 0.0.0.0 -p 3000
```

Open [http://localhost:3000](http://localhost:3000).

## Features — 19 Screens

| Feature | Route | Description |
|---------|-------|-------------|
| Dashboard | `/` | HUD with agent status, health, model info |
| Chat | `/chat` | SSE streaming chat with session tabs |
| Models | `/models` | Browse, switch, and probe AI models |
| Sessions | `/sessions` | View, search, and resume past sessions |
| Skills | `/skills` | Browse and toggle agent skills |
| Memory | `/memory` | View, search, and edit agent memory |
| Files | `/files` | Browse and edit `~/.hermes` workspace files |
| Config | `/config` | Full YAML editor for `config.yaml` |
| Logs | `/logs` | Live log tailing with level filtering |
| Cron | `/cron_jobs` | Manage scheduled agent tasks |
| Gateway | `/gateway` | Monitor and toggle Discord, Telegram, etc. |
| Missions | `/missions` | Define and run autonomous AI missions |
| Profiles | `/profiles` | Save/load model + config presets |
| Tools | `/tools` | Live tool execution stream |
| Inspector | `/inspector` | Deep-dive session analysis |
| Webhooks | `/webhooks` | Event-driven webhook subscriptions |
| Usage | `/usage` | Token usage, session counts, cost estimates |
| Setup | `/setup` | Hermes installation and configuration wizard |
| Providers | `/providers` | Manage API providers with connection testing |

## Architecture

```
Browser ──► Rails (port 3000) ──► Rust Backend (port 9120) ──► Hermes CLI
```

The Rails app never calls `hermes` directly — all requests go through the Rust backend at `../backend/`.

## Theme System

The same 29 themes from the Flutter app are available in the web dashboard. Theme switching is a form POST that sets a session cookie — no JavaScript required.

## Data Models (SQLite)

| Model | Purpose |
|-------|---------|
| `Profile` | Saved model + config + skills presets |
| `Mission` | Conductor agent mission definitions |
| `OrchestrationRun` | Multi-agent task records |
| `Webhook` | Event-driven webhook subscriptions |
| `CachedSkill` | Synced from `hermes skills list` |
| `CachedMemory` | Synced from `hermes memory` |
| `UsageSnapshot` | Token usage and analytics |

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `HERMES_BACKEND_URL` | `http://127.0.0.1:9120` | Rust backend location |

---

Built as part of the [Hermes Wingman](https://github.com/synthalorian/hermes-wingman) monorepo by **synth** ([synthalorian](https://github.com/synthalorian)) with assistance from **synthclaw** 🎹🦞.

*This is the wave. 🎹🦞🌆*