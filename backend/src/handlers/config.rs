use axum::{extract::State, http::StatusCode, response::Json};
use std::sync::Arc;
use serde::{Deserialize, Serialize};
use crate::state::AppState;
use crate::platform::{hermes_binary_path, hermes_home_dir, run_hermes};
use crate::helpers::{read_config, read_file, get_active_model};
use std::process::Command;
use crate::models::{discover_models, probe_model_via_curl, ModelEntry, ModelsResponse};
use crate::chat::{handle_chat, ChatRequest, ChatResponse};

// ── HTTP Handlers ──────────────────────────────────────────────────────────

pub async fn health(State(_state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    let hermes_path = hermes_binary_path();
    let hermes_check = Command::new(&hermes_path)
        .arg("--version")
        .output()
        .ok();

    let (installed, version) = match hermes_check {
        Some(output) if output.status.success() => {
            let v = String::from_utf8_lossy(&output.stdout).trim().to_string();
            (true, v)
        }
        _ => (false, String::new()),
    };

    Json(serde_json::json!({
        "status": "ok",
        "hermes_installed": installed,
        "hermes_version": version,
        "config_exists": _state.config_path().exists(),
    }))
}

pub async fn get_config(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    let raw = read_file(&state.config_path()).unwrap_or_default();
    let parsed: serde_json::Value = serde_yaml::from_str(&raw)
        .map(|v: serde_yaml::Value| {
            serde_json::to_value(v).unwrap_or(serde_json::Value::Null)
        })
        .unwrap_or(serde_json::Value::Null);

    Json(serde_json::json!({
        "raw": raw,
        "parsed": parsed,
        "path": state.config_path().to_string_lossy(),
    }))
}

pub async fn write_config(
    State(state): State<Arc<AppState>>,
    Json(body): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let content = body["content"].as_str().ok_or(StatusCode::BAD_REQUEST)?;
    std::fs::write(&state.config_path(), content).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(serde_json::json!({"success": true})))
}

pub async fn update_config(
    State(state): State<Arc<AppState>>,
    Json(body): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let updates = body["updates"].as_object().ok_or(StatusCode::BAD_REQUEST)?;
    let raw = read_file(&state.config_path()).unwrap_or_default();
    let mut result = raw.clone();

    for (key, value) in updates {
        let search_key = if key.contains('.') {
            key.rsplit('.').next().unwrap_or(key)
        } else {
            key
        };

        let val_str = if let Some(s) = value.as_str() {
            s.to_string()
        } else if let Some(n) = value.as_u64() {
            n.to_string()
        } else if let Some(b) = value.as_bool() {
            b.to_string()
        } else {
            continue;
        };

        let mut found = false;
        let mut new_lines: Vec<String> = Vec::new();
        for line in result.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with(&format!("{}:", search_key)) {
                let indent = line.len() - line.trim_start().len();
                new_lines.push(format!("{}{}: {}", " ".repeat(indent), search_key, val_str));
                found = true;
            } else {
                new_lines.push(line.to_string());
            }
        }

        if found {
            result = new_lines.join("\n");
        } else {
            if !result.ends_with('\n') {
                result.push('\n');
            }
            result.push_str(&format!("{}: {}\n", key, val_str));
        }
    }

    std::fs::write(&state.config_path(), &result).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(serde_json::json!({"success": true})))
}

pub async fn get_models(State(state): State<Arc<AppState>>) -> Json<ModelsResponse> {
    let mut response = discover_models().await;
    // Override "current" with the in-memory selection if set
    let active = get_active_model(&state);
    if !active.is_empty() {
        response.current = active;
    }
    Json(response)
}

#[derive(Deserialize)]
struct SwitchModelRequest {
    model: String,
}

pub async fn switch_model(
    State(state): State<Arc<AppState>>,
    Json(body): Json<SwitchModelRequest>,
) -> Json<serde_json::Value> {
    // Store model selection in-memory only — does NOT touch config.yaml
    // This keeps Wingman's model selection isolated from Hermes CLI/Discord/etc.
    match state.override_model.lock() {
        Ok(mut override_model) => {
            let model = body.model.clone();
            if model.is_empty() {
                *override_model = None;
                eprintln!("[Hermes Wingman] Cleared model override — falling back to config.yaml");
            } else {
                *override_model = Some(model.clone());
                eprintln!("[Hermes Wingman] Model override set to: {}", model);
            }
            Json(serde_json::json!({"success": true, "model": model, "overridden": !model.is_empty()}))
        }
        Err(e) => Json(serde_json::json!({"success": false, "error": format!("Lock poisoned: {}", e)})),
    }
}

#[derive(Deserialize)]
struct ProbeRequest {
    model: String,
}

pub async fn probe_model_handler(
    Json(body): Json<ProbeRequest>,
) -> Json<serde_json::Value> {
    let config = read_config();
    let (status, error) = probe_model_via_curl(&body.model, &config);

    // Cache probe result
    let cache_path = hermes_home_dir().join("wingman_probed.json");
    if let Ok(content) = read_file(&cache_path) {
        let mut cache: serde_json::Value = serde_json::from_str(&content).unwrap_or(serde_json::json!({}));
        cache[&body.model] = serde_json::json!({"status": status, "error": error, "probed_at": chrono::Utc::now().to_rfc3339()});
        let _ = std::fs::write(&cache_path, serde_json::to_string_pretty(&cache).unwrap_or_default());
    }

    Json(serde_json::json!({"model": body.model, "status": status, "error": error}))
}

pub async fn chat_handler(
    State(state): State<Arc<AppState>>,
    Json(body): Json<ChatRequest>,
) -> Json<ChatResponse> {
    let current_model = get_active_model(&state);
    Json(handle_chat(body, &current_model))
}

/// Validate the current Hermes configuration.
pub async fn validate_config(
    State(state): State<Arc<AppState>>,
) -> Json<serde_json::Value> {
    let raw = read_file(&state.config_path()).unwrap_or_default();
    match serde_yaml::from_str::<serde_yaml::Value>(&raw) {
        Ok(cfg) => {
            let mut issues = Vec::new();
            if cfg["model"].is_null() {
                issues.push("No default model configured");
            }
            if cfg["providers"].is_null() {
                issues.push("No providers configured");
            }
            Json(serde_json::json!({
                "valid": issues.is_empty(),
                "issues": issues,
            }))
        }
        Err(e) => Json(serde_json::json!({
            "valid": false,
            "issues": vec![format!("YAML parse error: {}", e)],
        })),
    }
}

#[derive(Deserialize)]
struct SessionsQuery {
    limit: Option<u32>,
}

