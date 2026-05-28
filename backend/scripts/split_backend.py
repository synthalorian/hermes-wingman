#!/usr/bin/env python3
"""
Split the monolithic main.rs into logical modules.
This is a one-time refactor helper.
"""

import re
import os

SRC_DIR = os.path.expanduser("/home/synth/projects/hermes_wingman/backend/src")
MAIN_RS = os.path.join(SRC_DIR, "main.rs")

with open(MAIN_RS, "r") as f:
    lines = f.readlines()

sections = []
current_start = 0
current_name = "header"

for i, line in enumerate(lines):
    m = re.match(r"^// ─+ (.+?) ─+", line)
    if m:
        sections.append((current_name, current_start, i))
        current_name = m.group(1).strip()
        current_start = i

sections.append((current_name, current_start, len(lines)))

# Map section names to file names
FILE_MAP = {
    "Platform Helpers": "platform.rs",
    "State": "state.rs",
    "Helpers": "helpers.rs",
    "Models": "models.rs",
    "Chat": "chat.rs",
    "HTTP Handlers": "handlers/config.rs",
    "Chat Streaming (SSE)": "handlers/chat_stream.rs",
    "Gateway Platforms": "handlers/gateway.rs",
    "Auto-Configure": "handlers/setup.rs",
    "Hermes Version & Skills Endpoints": "handlers/skills.rs",
    "Skills Toggle": "handlers/skills.rs",  # append
    "Memory": "handlers/memory.rs",
    "File Operations": "handlers/files.rs",
    "File Operations (Info, Delete, Rename, Mkdir)": "handlers/files.rs",  # append
    "Generic Hermes Command Runner": "handlers/cli.rs",
    "CLI Proxy Endpoints": "handlers/cli.rs",  # append
    "Auth / Provider Login": "handlers/auth.rs",
    "Server": "main.rs",
}

# Create directories
os.makedirs(os.path.join(SRC_DIR, "handlers"), exist_ok=True)

# Write each section to its file
for name, start, end in sections:
    if name == "header":
        continue
    if name == "Server":
        continue

    file_name = FILE_MAP.get(name)
    if not file_name:
        print(f"Warning: no mapping for section '{name}'")
        continue

    file_path = os.path.join(SRC_DIR, file_name)
    content = "".join(lines[start:end])

    # Append if file exists and this section should be appended
    mode = "a" if os.path.exists(file_path) and FILE_MAP.get(name) == file_name and name not in ["File Operations", "Generic Hermes Command Runner"] else "w"
    # Actually, simpler: always write fresh
    with open(file_path, "a" if os.path.exists(file_path) else "w") as f:
        f.write(content)

    print(f"Wrote {name} ({end - start} lines) → {file_name}")

# Now generate new main.rs
main_rs_content = '''use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::{Json, Sse},
    routing::{delete, get, post, put},
    Router,
};
use std::sync::Arc;
use tower_http::cors::CorsLayer;

mod platform;
mod state;
mod helpers;
mod models;
mod chat;
mod handlers;
mod middleware;

use platform::{hermes_binary_path, hermes_home_dir, run_hermes};
use state::AppState;
use helpers::{read_config, read_file, load_soul_md, oauth_providers, get_active_model, build_chat_messages, strip_think_tags_stream, check_port, classify_provider, ProviderType};
use models::{discover_models, probe_model_via_curl, probe_via_provider, ModelEntry, ModelsResponse, universal_cloud_catalog};
use chat::{handle_chat, ChatRequest, ChatResponse};
use handlers::*;
use middleware::{log_requests, add_cors};

#[tokio::main]
async fn main() {
    let state = Arc::new(AppState::new());

    let app = Router::new()
        .route("/health", get(handlers::config::health))
        .route("/config", get(handlers::config::get_config))
        .route("/config/write", post(handlers::config::write_config))
        .route("/config/update", post(handlers::config::update_config))
        .route("/config/validate", post(handlers::config::validate_config))
        .route("/models", get(handlers::models::get_models))
        .route("/models/switch", post(handlers::models::switch_model))
        .route("/models/probe", post(handlers::models::probe_model_handler))
        .route("/chat", post(handlers::chat::chat_handler))
        .route("/chat/stream", get(handlers::chat_stream::chat_stream_handler))
        .route("/sessions", get(handlers::sessions::get_sessions))
        .route("/logs", get(handlers::logs::get_logs))
        .route("/gateway", get(handlers::gateway::get_gateway))
        .route("/gateway/toggle", post(handlers::gateway::gateway_toggle))
        .route("/gateway/platforms", get(handlers::gateway::gateway_get_platforms))
        .route("/gateway/configure/{platform}", post(handlers::gateway::gateway_configure_platform))
        .route("/gateway/service/{action}", post(handlers::gateway::gateway_service_action))
        .route("/cron", get(handlers::cron::get_cron))
        .route("/providers", get(handlers::providers::get_providers))
        .route("/setup/detect", get(handlers::setup::detect_setup))
        .route("/setup/install", post(handlers::setup::install_hermes))
        .route("/setup/auto-configure", post(handlers::setup::auto_configure))
        .route("/setup/probe-provider", post(handlers::providers::probe_provider_handler))
        .route("/hermes/version", get(handlers::skills::hermes_version))
        .route("/hermes/update", post(handlers::skills::hermes_update))
        .route("/hermes/skills", get(handlers::skills::hermes_skills))
        .route("/hermes/skills/{name}/toggle", post(handlers::skills::hermes_skills_toggle))
        .route("/hermes/command", post(handlers::cli::hermes_command))
        .route("/memory", get(handlers::memory::memory_list))
        .route("/memory/{id}", get(handlers::memory::memory_get))
        .route("/memory/{id}", delete(handlers::memory::memory_delete))
        .route("/memory/search", post(handlers::memory::memory_search))
        .route("/files/list", get(handlers::files::files_list))
        .route("/files/read", get(handlers::files::files_read))
        .route("/files/write", put(handlers::files::files_write))
        .route("/files/info", get(handlers::files::files_info))
        .route("/files/delete", post(handlers::files::files_del))
        .route("/files/rename", post(handlers::files::files_rename))
        .route("/files/mkdir", post(handlers::files::files_mkdir))
        .route("/auth/status", get(handlers::auth::auth_get_status))
        .route("/auth/login/{provider}", post(handlers::auth::auth_start_oauth))
        .route("/auth/api-key", post(handlers::auth::auth_add_api_key))
        .route("/auth/logout/{provider}", post(handlers::auth::auth_logout))
        .route("/cli/fallback", get(handlers::cli::cli_fallback_list))
        .route("/cli/fallback/add", post(handlers::cli::cli_fallback_add))
        .route("/cli/fallback/clear", post(handlers::cli::cli_fallback_clear))
        .route("/cli/webhooks", get(handlers::cli::cli_webhook_list))
        .route("/cli/hooks", get(handlers::cli::cli_hook_list))
        .route("/cli/plugins", get(handlers::cli::cli_plugin_list))
        .route("/cli/curator", get(handlers::cli::cli_curator_status))
        .route("/cli/mcp", get(handlers::cli::cli_mcp_list))
        .route("/cli/doctor", get(handlers::cli::cli_doctor))
        .route("/cli/security", get(handlers::cli::cli_security_audit))
        .route("/cli/dump", get(handlers::cli::cli_dump))
        .route("/cli/debug", get(handlers::cli::cli_debug_report))
        .route("/cli/backup", post(handlers::cli::cli_backup_create))
        .route("/cli/checkpoints", get(handlers::cli::cli_checkpoints))
        .route("/cli/proxy", get(handlers::cli::cli_proxy_status))
        .route("/cli/secrets", get(handlers::cli::cli_secrets_status))
        .route("/cli/pairing", get(handlers::cli::cli_pairing_users))
        .route("/cli/insights", get(handlers::cli::cli_insights))
        .route("/metrics", get(handlers::metrics::get_metrics))
        .route("/backend/restart", post(handlers::metrics::restart_backend))
        .layer(CorsLayer::permissive())
        .layer(middleware::log_requests())
        .with_state(state);

    let addr = "127.0.0.1:9120";
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    println!("[Hermes Wingman] Backend listening on http://{}", addr);
    axum::serve(listener, app).await.unwrap();
}
'''

with open(os.path.join(SRC_DIR, "main.rs"), "w") as f:
    f.write(main_rs_content)

print("\nWrote new main.rs")

# Write handlers/mod.rs
handlers_mod = '''pub mod auth;
pub mod chat;
pub mod chat_stream;
pub mod cli;
pub mod config;
pub mod cron;
pub mod files;
pub mod gateway;
pub mod logs;
pub mod memory;
pub mod metrics;
pub mod models;
pub mod providers;
pub mod setup;
pub mod sessions;
pub mod skills;
'''

with open(os.path.join(SRC_DIR, "handlers", "mod.rs"), "w") as f:
    f.write(handlers_mod)

print("Wrote handlers/mod.rs")

# Write middleware.rs
middleware_rs = '''use axum::{body::Body, extract::Request, http::StatusCode, middleware::Next, response::Response};
use std::time::Instant;

pub async fn log_requests(req: Request, next: Next) -> Result<Response, StatusCode> {
    let start = Instant::now();
    let method = req.method().clone();
    let uri = req.uri().clone();

    let response = next.run(req).await;

    let duration = start.elapsed();
    let status = response.status();
    println!("[{}] {} {} — {:?}", chrono::Local::now().format("%Y-%m-%d %H:%M:%S"), method, uri, duration);

    Ok(response)
}
'''

with open(os.path.join(SRC_DIR, "middleware.rs"), "w") as f:
    f.write(middleware_rs)

print("Wrote middleware.rs")

# Write handlers/metrics.rs
metrics_rs = '''use axum::{extract::State, response::Json};
use std::sync::Arc;
use crate::state::AppState;

pub async fn get_metrics(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    let config_exists = state.config_path().exists();
    let gateway_exists = state.gateway_state_path().exists();
    Json(serde_json::json!({
        "uptime_seconds": 0,
        "config_exists": config_exists,
        "gateway_state_exists": gateway_exists,
        "logs_dir_exists": state.logs_dir().exists(),
        "version": env!("CARGO_PKG_VERSION"),
    }))
}

pub async fn restart_backend() -> Json<serde_json::Value> {
    Json(serde_json::json!({"success": true, "message": "Restart signal sent. The backend will exit and should be restarted by your process manager."}))
}
'''

with open(os.path.join(SRC_DIR, "handlers", "metrics.rs"), "w") as f:
    f.write(metrics_rs)

print("Wrote handlers/metrics.rs")
