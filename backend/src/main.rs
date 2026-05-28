use axum::{
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

use state::AppState;

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
        .route("/files/delete", post(handlers::files::files_delete))
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
        .route("/cli/hooks", get(handlers::cli::cli_hooks_list))
        .route("/cli/plugins", get(handlers::cli::cli_plugins_list))
        .route("/cli/curator", get(handlers::cli::cli_curator_status))
        .route("/cli/mcp", get(handlers::cli::cli_mcp_list))
        .route("/cli/doctor", get(handlers::cli::cli_doctor))
        .route("/cli/security", get(handlers::cli::cli_security_audit))
        .route("/cli/dump", get(handlers::cli::cli_dump))
        .route("/cli/debug", get(handlers::cli::cli_debug_share))
        .route("/cli/backup", post(handlers::cli::cli_backup_create))
        .route("/cli/checkpoints", get(handlers::cli::cli_checkpoints_status))
        .route("/cli/proxy", get(handlers::cli::cli_proxy_status))
        .route("/cli/secrets", get(handlers::cli::cli_secrets_status))
        .route("/cli/pairing", get(handlers::cli::cli_pairing_list))
        .route("/cli/insights", get(handlers::cli::cli_insights))
        .route("/metrics", get(handlers::metrics::get_metrics))
        .route("/backend/restart", post(handlers::metrics::restart_backend))
        .layer(CorsLayer::permissive())
        .layer(axum::middleware::from_fn(middleware::log_requests))
        .with_state(state);

    let addr = "127.0.0.1:9120";
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    println!("[Hermes Wingman] Backend listening on http://{}", addr);
    axum::serve(listener, app).await.unwrap();
}
