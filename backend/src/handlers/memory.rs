use axum::{extract::{Path, State}, http::StatusCode, response::Json, routing::delete};
use std::sync::Arc;
use std::path::PathBuf;
use serde::{Deserialize};
use crate::state::AppState;
use crate::platform::{hermes_home_dir, run_hermes};
use crate::helpers::read_file;

// ── Memory ──────────────────────────────────────────────────────────────────

pub async fn memory_list() -> Json<serde_json::Value> {
    // Read MEMORY.md and USER.md from ~/.hermes/memories/
    let mem_path = hermes_home_dir().join("memories").join("MEMORY.md");
    let user_path = hermes_home_dir().join("memories").join("USER.md");
    
    let memory_content = read_file(&mem_path).unwrap_or_default();
    let user_content = read_file(&user_path).unwrap_or_default();
    
    // Parse MEMORY.md into entries (separated by §)
    let mut entries = Vec::new();
    for section in memory_content.split('§') {
        let trimmed = section.trim();
        if trimmed.is_empty() { continue; }
        let lines: Vec<&str> = trimmed.lines().collect();
        let first_line = lines.first().unwrap_or(&"");
        let key = if first_line.starts_with('#') { first_line.trim_start_matches('#').trim().to_string() }
                   else if first_line.starts_with("**") { first_line.trim_matches('*').to_string() }
                   else { first_line.to_string() };
        let content = if lines.len() > 1 { lines[1..].join("\n").trim().to_string() } else { String::new() };
        
        entries.push(serde_json::json!({
            "key": if key.is_empty() { format!("Entry {}", entries.len() + 1) } else { key },
            "content": content.chars().take(200).collect::<String>(),
            "type": "memory",
        }));
    }
    
    // Add USER.md as an entry
    if !user_content.is_empty() {
        entries.push(serde_json::json!({
            "key": "User Profile (USER.md)",
            "content": user_content.chars().take(200).collect::<String>(),
            "type": "user_profile",
        }));
    }
    
    // Get memory provider status
    let status = match run_hermes(&["memory", "status"]) {
        Ok((stdout, _, _)) => stdout.trim().to_string(),
        Err(_) => String::new(),
    };

    Json(serde_json::json!({
        "success": true,
        "entries": entries,
        "count": entries.len(),
        "status": status,
    }))
}

pub async fn memory_get(
    axum::extract::Path(id): axum::extract::Path<String>,
) -> Json<serde_json::Value> {
    match run_hermes(&["memory", "get", &id]) {
        Ok((stdout, _stderr, code)) => {
            Json(serde_json::json!({
                "success": code == 0,
                "id": id,
                "content": stdout.trim(),
            }))
        }
        Err(e) => Json(serde_json::json!({
            "success": false,
            "error": e,
        })),
    }
}

pub async fn memory_delete(
    axum::extract::Path(id): axum::extract::Path<String>,
) -> Json<serde_json::Value> {
    match run_hermes(&["memory", "delete", &id]) {
        Ok((_stdout, _stderr, code)) => {
            Json(serde_json::json!({
                "success": code == 0,
                "id": id,
            }))
        }
        Err(e) => Json(serde_json::json!({
            "success": false,
            "error": e,
        })),
    }
}

#[derive(Deserialize)]
struct MemorySearchQuery {
    query: Option<String>,
}

pub async fn memory_search(
    Json(body): Json<serde_json::Value>,
) -> Json<serde_json::Value> {
    let query = body["query"].as_str().unwrap_or("");
    if query.is_empty() {
        return Json(serde_json::json!({
            "success": false,
            "entries": [],
            "error": "query is required",
        }));
    }
    match run_hermes(&["memory", "search", query]) {
        Ok((stdout, _stderr, code)) => {
            let entries: Vec<&str> = stdout.lines().filter(|l| !l.trim().is_empty()).collect();
            Json(serde_json::json!({
                "success": code == 0,
                "entries": entries,
                "count": entries.len(),
            }))
        }
        Err(e) => Json(serde_json::json!({
            "success": false,
            "entries": [],
            "error": e,
        })),
    }
}

