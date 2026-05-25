# Hermes Wingman Webapp + GUI Enhancement Plan

> **Stack:** Ruby on Rails 8.1 + Hotwire/Turbo + Tailwind CSS v4 (synthwave84) + SQLite
> **Sister:** Enhanced Flutter GUI sharing the same Rust backend
> **Backend:** Existing Rust axum server on port 9120 (21 endpoints)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│                   Browser (Rails)                      │
│  Hotwire/Turbo ──── SSE streaming ──── Stimulus JS    │
└──────────────────────┬───────────────────────────────┘
                       │ http://localhost:3000
                       ▼
┌──────────────────────────────────────────────────────┐
│              Rails Web App (Port 3000)                 │
│                                                        │
│  ┌─────────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │ Controllers  │  │ Services │  │  Action Cable     │  │
│  │ (RESTful)    │  │ (API     │  │  (WebSocket)      │  │
│  │              │  │  client) │  │  - Chat streaming │  │
│  └──────┬───────┘  └────┬─────┘  │  - Live tool exec│  │
│         │               │        └──────────────────┘  │
│         ▼               ▼                              │
│  ┌─────────────────────────────────────────────┐       │
│  │           Rust Backend Proxy                 │       │
│  │  (HermesApiService — HTTP calls to :9120)    │       │
│  └──────────────────────┬──────────────────────┘       │
└─────────────────────────┼──────────────────────────────┘
                          │ http://localhost:9120
                          ▼
┌──────────────────────────────────────────────────────┐
│           Rust Backend (Axum, Port 9120)               │
│  /health, /config, /models, /chat/stream, /sessions,  │
│  /logs, /gateway, /cron, /providers, /setup/*,        │
│  /hermes/*                                             │
│                                                        │
│  NEW ENDPOINTS TO ADD:                                 │
│  /tools/live, /skills/*, /memory/*, /files/*,         │
│  /profiles/*, /missions/*, /orchestration/*,           │
│  /webhooks/*, /usage/*                                 │
└──────┬───────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────┐
│  Hermes Agent CLI     │
│  (hermes binary on    │
│   system PATH)        │
└──────────────────────┘
```

## Feature Catalog

### Phase 1 — Core Port (Rails Webapp, mirrors existing GUI)

| # | Feature | Rails Routes | Backend API |
|---|---------|-------------|-------------|
| 1 | Dashboard HUD | `GET /` | `/health`, `/models`, `/hermes/version` |
| 2 | Chat (SSE streaming) | `GET /chat`, `POST /chat/messages` | `/chat`, `/chat/stream` |
| 3 | Session Manager | `GET /sessions`, `GET /sessions/:id` | `/sessions` |
| 4 | Model Browser | `GET /models`, `POST /models/:name/switch` | `/models`, `/models/switch` |
| 5 | Provider Config | `GET /providers`, `POST /providers/probe` | `/providers`, `/setup/probe-provider` |
| 6 | Config Editor | `GET /config`, `PUT /config` | `/config`, `/config/write` |
| 7 | Log Viewer | `GET /logs?level=&lines=` | `/logs` |
| 8 | Cron Manager | `GET /cron`, `POST /cron/:id/toggle` | `/cron` |
| 9 | Gateway Dashboard | `GET /gateway`, `POST /gateway/toggle` | `/gateway`, `/gateway/toggle` |
| 10 | Setup Wizard | `GET /setup`, `POST /setup/*` | `/setup/detect`, `/setup/*` |

### Phase 2 — New Features (Webapp + GUI)

| # | Feature | Description | Backend Needed? |
|---|---------|-------------|-----------------|
| 11 | Live Tool Execution | Real-time stream of tools being called by the agent | New: `GET /chat/stream` enhanced |
| 12 | Skills Browser | Browse, search, enable/disable installed skills | New: `GET /skills`, `POST /skills/:name/toggle` |
| 13 | Memory Viewer | Read/edit agent memory entries, semantic search | New: `GET /memory`, `POST /memory/search` |
| 14 | File Explorer | Browse ~/.hermes workspace, view/edit files | New: `GET /files/*`, `PUT /files/*` |
| 15 | Provider GUI Editor | Visual provider config with form fields instead of YAML | Uses existing `/config` |
| 16 | Inspector Panel | Deep-dive into agent thinking, tool calls, decisions | New: `GET /sessions/:id/inspect` |
| 17 | Conductor Missions | Define, schedule, track AI agent missions | New: `POST /missions`, `GET /missions` |
| 18 | Agent Orchestration | Multi-agent coordination dashboard, task distribution | New: `POST /orchestrate`, `GET /orchestrate/status` |
| 19 | Profiles | Save/load model+config+skills+theme presets | New: `POST /profiles`, `GET /profiles` |
| 20 | Webhook Manager | CRUD for webhook subscriptions | New: `POST /webhooks`, `GET /webhooks` |
| 21 | Usage Analytics | Token usage, session counts, cost estimates | New: `GET /usage` |
| 22 | Theme System | Synthwave84 color schemes, CRT effects, dark modes | Built into Rails Tailwind |
| 23 | Health Monitor | Real-time agent health, uptime, alerts | Uses `/health` |

### Phase 3 — Flutter GUI Enhancements

| # | Feature | New Flutter Screen? |
|---|---------|---------------------|
| 24 | Live Tool Exec overlay | Widget added to Chat screen |
| 25 | Skills screen | New screen (exists as Tools but shallow) |
| 26 | Memory screen | New screen |
| 27 | File Browser | New screen |
| 28 | Inspector Panel | New screen |
| 29 | Missions screen | New screen |
| 30 | Orchestration Dashboard | New screen |
| 31 | Profiles screen | New screen |
| 32 | Usage/Analytics | Dashboard widget |
| 33 | Health Monitor | Dashboard widget |

## Data Model (Rails side — local metadata)

```ruby
# Profiles — saved model+config+skills presets
Profile:
  id, name, description, model_name, provider_name,
  config_overrides: json, skills: json, theme: string,
  created_at, updated_at

# Missions — conductor agent missions
Mission:
  id, name, description, prompt, schedule, status,
  assigned_agent: string, max_turns: integer,
  last_run_at, next_run_at, output: text,
  created_at, updated_at

# Orchestration Runs — multi-agent task records
OrchestrationRun:
  id, name, description, status, agent_count: integer,
  agents: json, tasks: json, results: json,
  started_at, completed_at, created_at

# Webhooks
Webhook:
  id, name, url, events: json, secret: string,
  active: boolean, last_triggered_at, created_at

# Cached Skills (synced from hermes skills list)
CachedSkill:
  id, name, description, category, enabled: boolean,
  version: string, path: string, created_at, updated_at

# Cached Memory Entries (synced from hermes memory)
CachedMemory:
  id, key, content, memory_type: string,
  tags: json, created_at, updated_at

# Usage Stats (polled periodically)
UsageSnapshot:
  id, session_count: integer, token_count: integer,
  active_models: json, recorded_at
```

## Rust Backend — New Endpoints

```rust
// Phase 2 New Routes
.route("/tools/live", get(tools_live_handler))         // SSE stream of tool calls
.route("/skills", get(list_skills_handler))              // List all skills
.route("/skills/:name/toggle", post(toggle_skill_handler)) // Enable/disable skill
.route("/memory", get(list_memory_handler))              // List memory entries
.route("/memory/:id", get(get_memory_handler))           // Get single memory
.route("/memory/:id", put(update_memory_handler))        // Update memory
.route("/memory/search", post(search_memory_handler))    // Semantic search
.route("/files/**path", get(read_file_handler))          // Read file
.route("/files/**path", put(write_file_handler))         // Write file
.route("/profiles", get(list_profiles_handler))          // List profiles
.route("/profiles", post(create_profile_handler))        // Create profile
.route("/profiles/:id", delete(delete_profile_handler))  // Delete profile
.route("/profiles/:id/apply", post(apply_profile_handler)) // Apply profile
.route("/missions", get(list_missions_handler))          // List missions
.route("/missions", post(create_mission_handler))        // Create mission
.route("/missions/:id", delete(delete_mission_handler))  // Delete mission
.route("/missions/:id/run", post(run_mission_handler))   // Execute mission
.route("/orchestrate", post(create_orchestration_handler))// Start orchestration
.route("/orchestrate/:id/status", get(orchestration_status_handler)) // Poll status
.route("/webhooks", get(list_webhooks_handler))           // List webhooks
.route("/webhooks", post(create_webhook_handler))         // Create webhook
.route("/webhooks/:id", delete(delete_webhook_handler))   // Delete webhook
.route("/usage", get(usage_handler))                      // Usage stats
```

## Rails Project Structure

```
hermes_wingman_web/              # New Rails 8.1 project
├── app/
│   ├── controllers/
│   │   ├── application_controller.rb
│   │   ├── dashboard_controller.rb    # HUD
│   │   ├── chat_controller.rb         # Chat + SSE
│   │   ├── sessions_controller.rb     # Session browser
│   │   ├── models_controller.rb       # Model browser
│   │   ├── providers_controller.rb    # Provider config
│   │   ├── config_controller.rb       # Config editor
│   │   ├── logs_controller.rb         # Log viewer
│   │   ├── cron_controller.rb         # Cron manager
│   │   ├── gateway_controller.rb      # Gateway dashboard
│   │   ├── skills_controller.rb       # Skills browser
│   │   ├── memory_controller.rb       # Memory viewer
│   │   ├── files_controller.rb        # File explorer
│   │   ├── tools_controller.rb        # Live tool exec
│   │   ├── inspector_controller.rb    # Inspector panel
│   │   ├── missions_controller.rb     # Conductor missions
│   │   ├── orchestration_controller.rb # Orchestration
│   │   ├── profiles_controller.rb     # Profiles
│   │   ├── webhooks_controller.rb     # Webhooks
│   │   └── usage_controller.rb        # Analytics
│   │
│   ├── services/
│   │   ├── hermes_api_service.rb      # HTTP client to :9120
│   │   ├── chat_stream_service.rb     # SSE stream handler
│   │   ├── skill_service.rb           # Skills sync + cache
│   │   ├── memory_service.rb          # Memory operations
│   │   ├── file_service.rb            # File system operations
│   │   ├── mission_service.rb         # Mission lifecycle
│   │   ├── orchestration_service.rb   # Multi-agent orchestration
│   │   ├── profile_service.rb         # Profile CRUD + apply
│   │   └── usage_service.rb           # Usage polling + cache
│   │
│   ├── models/
│   │   ├── profile.rb
│   │   ├── mission.rb
│   │   ├── orchestration_run.rb
│   │   ├── webhook.rb
│   │   ├── cached_skill.rb
│   │   ├── cached_memory.rb
│   │   └── usage_snapshot.rb
│   │
│   ├── views/
│   │   ├── layouts/
│   │   │   └── application.html.erb   # Synthwave84 layout
│   │   ├── dashboard/
│   │   ├── chat/
│   │   ├── sessions/
│   │   ├── models/
│   │   ├── providers/
│   │   ├── config/
│   │   ├── logs/
│   │   ├── cron/
│   │   ├── gateway/
│   │   ├── skills/
│   │   ├── memory/
│   │   ├── files/
│   │   ├── tools/
│   │   ├── inspector/
│   │   ├── missions/
│   │   ├── orchestration/
│   │   ├── profiles/
│   │   ├── webhooks/
│   │   └── usage/
│   │
│   ├── javascript/
│   │   ├── application.js
│   │   ├── controllers/
│   │   │   ├── chat_controller.js         # Stimulus: SSE chat
│   │   │   ├── dashboard_controller.js    # Stimulus: live stats
│   │   │   ├── log_stream_controller.js   # Stimulus: tail logs
│   │   │   ├── tool_stream_controller.js  # Stimulus: live tool exec
│   │   │   └── theme_controller.js        # Stimulus: theme toggle
│   │   └── channels/
│   │       ├── chat_channel.js            # Action Cable: chat
│   │       └── tools_channel.js           # Action Cable: tool exec
│   │
│   └── assets/
│       └── tailwind/
│           └── application.css            # Synthwave84 theme
│
├── config/
│   ├── routes.rb
│   └── ...
├── db/
│   └── migrate/
└── ...
```

## UI Design — Synthwave84 Aesthetic

The webapp gets a full synthwave84 treatment:

- **Background:** Deep purple-to-black gradient (#0d0221 → #240037)
- **Cards:** Glass-morphism with purple borders and backdrop blur
- **Text:** Neon cyan (#00f0ff) headers, white body, dim purple secondary
- **Accents:** Pink (#ff2d95), cyan (#00f0ff), purple (#b829f0), yellow (#f0e829)
- **Effects:** CRT scanline overlay, horizon glow, subtle grid pattern
- **Monospace:** 3270 Nerd Font for code/data, system sans for UI
- **Borders:** Thin purple borders with subtle glow
- **Status dots:** Animated pulsing dots for live indicators
- **Animations:** 200ms ease transitions, subtle hover glows

## Implementation Order

1. **Scaffold Rails project** — `rails new`, Tailwind v4 setup, synthwave84 theme
2. **Build HermesApiService** — HTTP client to all Rust endpoints
3. **Build Dashboard** — HUD with health, model, status widgets
4. **Build Chat** — SSE streaming, session tabs, markdown rendering
5. **Build Sessions** — Session list, search, resume
6. **Build Models** — Model browser, switch, probe
7. **Build Config** — YAML editor with syntax highlighting
8. **Build Logs** — Live tailing, level filter
9. **Build Cron** — Cron job list, enable/disable
10. **Build Gateway** — Platform status cards, toggle
11. **Build Providers** — Provider list, add, probe
12. **Build Skills** — Skills browser, search, toggle
13. **Build Memory** — Memory viewer, search, edit
14. **Build File Explorer** — File tree, view, edit
15. **Build Live Tools** — SSE tool execution stream
16. **Build Inspector** — Session deep-dive panel
17. **Build Missions** — CRUD + execution
18. **Build Orchestration** — Multi-agent dashboard
19. **Build Profiles** — Save/load presets
20. **Build Webhooks** — CRUD
21. **Build Analytics** — Usage stats, charts
22. **Enhance Flutter GUI** — Port Phase 2 features to Flutter

---

*This is the wave. 🌊*
