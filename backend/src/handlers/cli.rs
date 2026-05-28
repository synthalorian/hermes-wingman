use serde::Deserialize;
use axum::response::Json;
use crate::platform::run_hermes;

// ── Generic Hermes Command Runner ────────────────────────────────────────────

#[derive(Deserialize)]
pub struct HermesCommandBody {
    args: Vec<String>,
}

pub async fn hermes_command(
    Json(body): Json<HermesCommandBody>,
) -> Json<serde_json::Value> {
    let str_args: Vec<&str> = body.args.iter().map(|s| s.as_str()).collect();
    match run_hermes(&str_args) {
        Ok((stdout, stderr, code)) => {
            Json(serde_json::json!({
                "success": code == 0,
                "stdout": stdout.trim(),
                "stderr": stderr.trim(),
                "exit_code": code,
            }))
        }
        Err(e) => Json(serde_json::json!({
            "success": false,
            "error": e,
            "exit_code": -1,
        })),
    }
}

// ── CLI Proxy Endpoints ────────────────────────────────────────────────────
// These wrap `hermes <subcommand>` calls for features that don't have
// dedicated Wingman screens yet. Each returns parsed JSON when possible.

pub async fn cli_fallback_list() -> Json<serde_json::Value> {
    match run_hermes(&["fallback", "list"]) {
        Ok((stdout, _, _)) => {
            let lines: Vec<String> = stdout.lines().map(|l| l.trim().to_string()).filter(|l| !l.is_empty()).collect();
            Json(serde_json::json!({ "success": true, "chain": lines }))
        },
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

pub async fn cli_fallback_add(Json(body): Json<serde_json::Value>) -> Json<serde_json::Value> {
    let provider = body["provider"].as_str().unwrap_or("");
    let model = body["model"].as_str().unwrap_or("");
    if provider.is_empty() || model.is_empty() {
        return Json(serde_json::json!({ "success": false, "error": "provider and model required" }));
    }
    match run_hermes(&["fallback", "add", "--provider", provider, "--model", model]) {
        Ok((stdout, _, code)) => Json(serde_json::json!({ "success": code == 0, "stdout": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

pub async fn cli_fallback_clear() -> Json<serde_json::Value> {
    match run_hermes(&["fallback", "clear"]) {
        Ok((stdout, _, code)) => Json(serde_json::json!({ "success": code == 0, "stdout": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

pub async fn cli_webhook_list() -> Json<serde_json::Value> {
    match run_hermes(&["webhook", "list"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "webhooks": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

pub async fn cli_hooks_list() -> Json<serde_json::Value> {
    match run_hermes(&["hooks", "list"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "hooks": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

pub async fn cli_plugins_list() -> Json<serde_json::Value> {
    match run_hermes(&["plugins", "list"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "plugins": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

pub async fn cli_curator_status() -> Json<serde_json::Value> {
    match run_hermes(&["curator", "status"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "status": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

pub async fn cli_mcp_list() -> Json<serde_json::Value> {
    match run_hermes(&["mcp", "list"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "servers": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

pub async fn cli_doctor() -> Json<serde_json::Value> {
    match run_hermes(&["doctor"]) {
        Ok((stdout, _, code)) => Json(serde_json::json!({ "success": code == 0, "output": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

pub async fn cli_security_audit() -> Json<serde_json::Value> {
    match run_hermes(&["security", "audit"]) {
        Ok((stdout, _, code)) => Json(serde_json::json!({ "success": code == 0, "output": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

pub async fn cli_dump() -> Json<serde_json::Value> {
    match run_hermes(&["dump"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "dump": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

pub async fn cli_debug_share() -> Json<serde_json::Value> {
    match run_hermes(&["debug", "share", "--local"]) {
        Ok((stdout, _, code)) => Json(serde_json::json!({ "success": code == 0, "output": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

pub async fn cli_backup_create() -> Json<serde_json::Value> {
    match run_hermes(&["backup", "--quick"]) {
        Ok((stdout, _, code)) => Json(serde_json::json!({ "success": code == 0, "output": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

pub async fn cli_checkpoints_status() -> Json<serde_json::Value> {
    match run_hermes(&["checkpoints", "status"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "status": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

pub async fn cli_proxy_status() -> Json<serde_json::Value> {
    match run_hermes(&["proxy", "status"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "status": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

pub async fn cli_secrets_status() -> Json<serde_json::Value> {
    match run_hermes(&["secrets", "bitwarden", "status"]) {
        Ok((stdout, _, code)) => Json(serde_json::json!({ "success": code == 0, "output": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

pub async fn cli_pairing_list() -> Json<serde_json::Value> {
    match run_hermes(&["pairing", "list"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "users": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

pub async fn cli_insights() -> Json<serde_json::Value> {
    match run_hermes(&["insights", "--days", "7"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "insights": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

