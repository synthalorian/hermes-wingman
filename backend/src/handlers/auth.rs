use axum::{extract::{Path, State}, response::Json};
use std::sync::Arc;
use serde::Deserialize;
use crate::state::AppState;
use crate::platform::hermes_binary_path;
use crate::helpers::read_file;

// ── Auth / Provider Login ───────────────────────────────────────────────────

/// Start an OAuth login flow for a provider.
/// Spawns `hermes auth add --type oauth --no-browser {provider}` in background,
/// captures the auth URL from stdout, and returns it to Flutter.
/// The hermes process continues running to handle the OAuth callback.
pub async fn auth_start_oauth(
    Path(provider): Path<String>,
    State(state): State<Arc<AppState>>,
) -> Json<serde_json::Value> {
    // Check if already logged in
    let auth_path = state.hermes_home.join("auth.json");
    let already_logged_in = read_file(&auth_path)
        .ok()
        .and_then(|c| serde_json::from_str::<serde_json::Value>(&c).ok())
        .and_then(|j| j["providers"].as_object().map(|p| p.contains_key(&provider)))
        .unwrap_or(false);

    if already_logged_in {
        return Json(serde_json::json!({
            "success": true,
            "provider": provider,
            "url": null,
            "status": "already_logged_in",
        }));
    }

    let binary = hermes_binary_path();

    // Spawn the auth process
    match tokio::process::Command::new(&binary)
        .args(["auth", "add", "--type", "oauth", "--no-browser", &provider])
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .env("PAGER", "cat")
        .spawn()
    {
        Ok(mut child) => {
            // Send "n\n" to stdin to decline re-importing existing creds
            if let Some(mut stdin) = child.stdin.take() {
                use tokio::io::AsyncWriteExt;
                let _ = stdin.write_all(b"n\n").await;
                // Drop stdin to signal EOF
                drop(stdin);
            }

            let output = child.wait_with_output().await;
            match output {
                Ok(out) => {
                    let stdout = String::from_utf8_lossy(&out.stdout).to_string();
                    let stderr = String::from_utf8_lossy(&out.stderr).to_string();
                    let combined = format!("{}\n{}", stdout, stderr);

                    // Try to find an auth URL in the output
                    let url_patterns = [
                        "https://",
                        "http://localhost",
                    ];
                    let mut auth_url: Option<String> = None;
                    for line in combined.lines() {
                        let trimmed = line.trim();
                        if url_patterns.iter().any(|p| trimmed.starts_with(p)) {
                            auth_url = Some(trimmed.to_string());
                            break;
                        }
                    }

                    // Check if auth was successful (auth.json updated)
                    let now_logged_in = read_file(&auth_path)
                        .ok()
                        .and_then(|c| serde_json::from_str::<serde_json::Value>(&c).ok())
                        .and_then(|j| j["providers"].as_object().map(|p| p.contains_key(&provider)))
                        .unwrap_or(false);

                    if now_logged_in {
                        Json(serde_json::json!({
                            "success": true,
                            "provider": provider,
                            "url": null,
                            "status": "logged_in",
                            "output": stdout.trim(),
                        }))
                    } else if let Some(url) = auth_url {
                        Json(serde_json::json!({
                            "success": true,
                            "provider": provider,
                            "url": url,
                            "status": "awaiting_auth",
                            "output": stdout.trim(),
                        }))
                    } else {
                        // Could not find URL — try with manual-paste flag
                        Json(serde_json::json!({
                            "success": false,
                            "provider": provider,
                            "url": null,
                            "status": "no_url",
                            "error": "Could not extract auth URL. The provider may not support OAuth or is already configured.",
                            "stdout": stdout.trim(),
                            "stderr": stderr.trim(),
                        }))
                    }
                }
                Err(e) => Json(serde_json::json!({
                    "success": false,
                    "error": format!("Auth process failed: {}", e),
                })),
            }
        }
        Err(e) => Json(serde_json::json!({
            "success": false,
            "error": format!("Failed to spawn auth process: {}", e),
        })),
    }
}

/// Login with an API key provider.
pub async fn auth_add_api_key(
    Json(body): Json<serde_json::Value>,
) -> Json<serde_json::Value> {
    let provider = body["provider"].as_str().unwrap_or("").to_string();
    let api_key = body["api_key"].as_str().unwrap_or("").to_string();

    if provider.is_empty() || api_key.is_empty() {
        return Json(serde_json::json!({
            "success": false,
            "error": "provider and api_key are required",
        }));
    }

    let binary = hermes_binary_path();
    match tokio::process::Command::new(&binary)
        .args(["auth", "add", "--type", "api-key", "--api-key", &api_key, &provider])
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .env("PAGER", "cat")
        .output()
        .await
    {
        Ok(out) => {
            let success = out.status.success();
            let stdout = String::from_utf8_lossy(&out.stdout).to_string();
            let stderr = String::from_utf8_lossy(&out.stderr).to_string();
            Json(serde_json::json!({
                "success": success,
                "provider": provider,
                "stdout": stdout.trim(),
                "stderr": stderr.trim(),
                "exit_code": out.status.code().unwrap_or(-1),
            }))
        }
        Err(e) => Json(serde_json::json!({
            "success": false,
            "error": format!("Failed to add auth: {}", e),
        })),
    }
}

/// Get auth status for all known providers.
pub async fn auth_get_status(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    // Read auth.json to find logged-in providers
    let auth_path = state.hermes_home.join("auth.json");
    let logged_in = read_file(&auth_path)
        .ok()
        .and_then(|c| serde_json::from_str::<serde_json::Value>(&c).ok())
        .and_then(|j| j["providers"].as_object().map(|p| {
            p.iter().map(|(k, v)| {
                let cred_type = v["type"].as_str().unwrap_or("unknown");
                (k.clone(), cred_type.to_string())
            }).collect::<Vec<_>>()
        }))
        .unwrap_or_default();

    // Check each known provider via status command
    let known_providers = vec![
        "nous", "anthropic", "xai", "xai-oauth", "gemini",
        "openai-codex", "openrouter", "deepseek", "zai",
    ];

    let mut providers = Vec::new();
    for p in &known_providers {
        let is_logged_in = logged_in.iter().any(|(name, _)| name == p);
        let cred_type = logged_in.iter()
            .find(|(name, _)| name == p)
            .map(|(_, t)| t.as_str())
            .unwrap_or("none");

        providers.push(serde_json::json!({
            "name": p,
            "status": if is_logged_in { "logged_in" } else { "not_logged_in" },
            "type": cred_type,
        }));
    }

    Json(serde_json::json!({
        "success": true,
        "providers": providers,
    }))
}

/// Log out a provider.
pub async fn auth_logout(
    Path(provider): Path<String>,
    State(_state): State<Arc<AppState>>,
) -> Json<serde_json::Value> {
    let binary = hermes_binary_path();
    match tokio::process::Command::new(&binary)
        .args(["auth", "logout", &provider])
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .env("PAGER", "cat")
        .output()
        .await
    {
        Ok(out) => {
            let success = out.status.success();
            Json(serde_json::json!({
                "success": success,
                "provider": provider,
                "stdout": String::from_utf8_lossy(&out.stdout).to_string().trim(),
                "stderr": String::from_utf8_lossy(&out.stderr).to_string().trim(),
            }))
        }
        Err(e) => Json(serde_json::json!({
            "success": false,
            "error": format!("Failed to logout: {}", e),
        })),
    }
}

