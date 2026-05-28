use axum::{extract::State, response::Json};
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
