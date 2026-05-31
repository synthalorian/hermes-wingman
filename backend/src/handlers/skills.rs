use axum::{extract::Path, response::Json};
use serde::{Deserialize};
use crate::platform::run_hermes;

// ── Hermes Version & Skills Endpoints ──────────────────────────────────────

pub async fn hermes_version() -> Json<serde_json::Value> {
    let output = run_hermes(&["--version"]);
    match output {
        Ok((stdout, stderr, code)) => {
            let output_str = if !stdout.trim().is_empty() { stdout.trim().to_string() }
                             else { stderr.trim().to_string() };
            Json(serde_json::json!({
                "success": code == 0,
                "version": output_str,
                "exit_code": code,
            }))
        }
        Err(e) => Json(serde_json::json!({
            "success": false,
            "version": "",
            "error": e,
        })),
    }
}

pub async fn hermes_update() -> Json<serde_json::Value> {
    let output = std::process::Command::new("pip3")
        .args(["install", "--upgrade", "hermes-agent"])
        .output();
    match output {
        Ok(o) => {
            let stdout = String::from_utf8_lossy(&o.stdout).to_string();
            let stderr = String::from_utf8_lossy(&o.stderr).to_string();
            let combined = if !stdout.trim().is_empty() { stdout.trim().to_string() }
                           else { stderr.trim().to_string() };
            Json(serde_json::json!({
                "success": o.status.success(),
                "output": combined,
                "exit_code": o.status.code().unwrap_or(-1),
            }))
        }
        Err(e) => Json(serde_json::json!({
            "success": false,
            "error": e.to_string(),
        })),
    }
}

pub async fn hermes_skills() -> Json<serde_json::Value> {
    let output = run_hermes(&["skills", "list"]);
    match output {
        Ok((stdout, _stderr, code)) => {
            let lines: Vec<&str> = stdout.lines().collect();
            let mut skills = Vec::new();
            for line in &lines {
                let trimmed = line.trim();
                // Table format: │ name │ category │ source │ trust │ status │
                if trimmed.starts_with('│') {
                    let parts: Vec<&str> = trimmed.split('│').collect();
                    if parts.len() >= 3 {
                        let name = parts.get(1).map(|s| s.trim()).unwrap_or("").to_string();
                        let category = parts.get(2).map(|s| s.trim()).unwrap_or("").to_string();
                        if !name.is_empty() && !name.contains("━━━") && !name.contains("───") && !name.starts_with("Name") {
                            // Remove ellipsis artifacts
                            let clean_name = name.replace('…', "").trim().to_string();
                            if !clean_name.is_empty() {
                                skills.push(serde_json::json!({
                                    "name": clean_name,
                                    "category": category,
                                    "description": if category.is_empty() { "No category" } else { &category },
                                }));
                            }
                        }
                    }
                }
            }
            Json(serde_json::json!({
                "success": code == 0,
                "skills": skills,
                "raw": stdout,
                "exit_code": code,
            }))
        }
        Err(e) => Json(serde_json::json!({
            "success": false,
            "skills": [],
            "error": e,
        })),
    }
}

// ── Skills Toggle ──────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct SkillToggleParams {
    action: Option<String>,
}

pub async fn hermes_skills_toggle(
    Path(name): Path<String>,
    Json(body): Json<serde_json::Value>,
) -> Json<serde_json::Value> {
    let action = body["action"].as_str().unwrap_or("toggle");
    let args: Vec<&str> = match action {
        "enable" => vec!["skills", "enable", &name],
        "disable" => vec!["skills", "disable", &name],
        _ => vec!["skills", "toggle", &name],
    };
    match run_hermes(&args) {
        Ok((stdout, _stderr, code)) => {
            Json(serde_json::json!({
                "success": code == 0,
                "name": name,
                "action": action,
                "output": stdout.trim(),
                "exit_code": code,
            }))
        }
        Err(e) => Json(serde_json::json!({
            "success": false,
            "error": e,
        })),
    }
}

