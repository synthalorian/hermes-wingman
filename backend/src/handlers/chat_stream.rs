// ── Chat Streaming (SSE) ─────────────────────────────────────────────────

use axum::{extract::{Query, State}, response::{Json, Sse, sse::Event}};
use std::sync::Arc;
use serde::{Deserialize};
use crate::state::AppState;
use crate::platform::{hermes_binary_path, run_hermes};
use crate::helpers::{read_config, oauth_providers, get_active_model, build_chat_messages, read_file};
use crate::handlers::setup::strip_think_tags_stream;
use futures::Stream;

#[derive(Deserialize)]
pub struct ChatStreamQuery {
    message: String,
    session_id: Option<String>,
}

pub async fn chat_stream_handler(
    State(state): State<Arc<AppState>>,
    Query(query): Query<ChatStreamQuery>,
) -> Sse<impl Stream<Item = Result<Event, std::convert::Infallible>>> {
    
    use tokio::sync::mpsc;
    use tokio_stream::wrappers::ReceiverStream;

    let (tx, rx) = mpsc::channel::<Result<Event, std::convert::Infallible>>(32);
    let message = query.message.clone();
    let session_id = query.session_id.clone();
    let active_model = get_active_model(&state);

    tokio::spawn(async move {
        let config = read_config();
        let current_model = if !active_model.is_empty() {
            &active_model
        } else {
            config["model"].as_str()
                .or_else(|| config["model"]["default"].as_str())
                .unwrap_or("")
        };

        if current_model.is_empty() {
            let evt = Event::default().data(r#"{"error":"no model configured"}"#);
            let _ = tx.send(Ok(evt)).await;
            let evt = Event::default().data("[DONE]");
            let _ = tx.send(Ok(evt)).await;
            return;
        }

        // Determine provider
        let prefix = current_model.split('/').next().unwrap_or("");
        let model_short = current_model.split('/').last().unwrap_or(current_model);
        let provider_name = match prefix {
            "x-ai" | "xai" | "grok" => {
                let mut found = "xai-oauth";
                if let Some(providers) = config["providers"].as_mapping() {
                    for (name, _) in providers {
                        let n = name.as_str().unwrap_or("");
                        if n.contains("xai") || n.contains("grok") { found = n; break; }
                    }
                }
                found
            }
            "llama-swap" => "llama-swap",
            "google" => "gemini",
            "anthropic" | "claude" => "anthropic",
            "openai" => "openai",
            "deepseek" | "nous" => "nous",
            _ => prefix,
        };

        let base_url = config["providers"][provider_name]["base_url"].as_str().unwrap_or("").to_string();
        let api_key = config["providers"][provider_name]["api_key"].as_str()
            .or_else(|| config["providers"][provider_name]["api_key_env"].as_str()
                .and_then(|env| std::env::var(env).ok())
                .map(|s| Box::leak(s.into_boxed_str()) as &str))
            .unwrap_or("")
            .to_string();

        if base_url.is_empty() || oauth_providers().contains(provider_name) {
            // Fallback to hermes CLI — use -z (oneshot) for clean output
            let mut args = vec!["-z", &message];
            if let Some(sid) = &session_id {
                if !sid.is_empty() {
                    args = vec!["--resume", sid, "-z", &message];
                }
            }
            match std::process::Command::new(hermes_binary_path()).args(&args).output() {
                Ok(output) if output.status.success() => {
                    let out = String::from_utf8_lossy(&output.stdout);
                    let evt = Event::default().data(serde_json::json!({"content": out}).to_string());
                    let _ = tx.send(Ok(evt)).await;
                }
                _ => {
                    let evt = Event::default().data(r#"{"error":"hermes command failed"}"#);
                    let _ = tx.send(Ok(evt)).await;
                }
            }
            let evt = Event::default().data("[DONE]");
            let _ = tx.send(Ok(evt)).await;
            return;
        }

        // Make streaming request to the provider
        let chat_url = format!("{}/chat/completions", base_url.trim_end_matches('/'));
        let messages = build_chat_messages(&message, session_id.as_deref());
        let payload = serde_json::json!({
            "model": model_short,
            "messages": messages,
            "max_tokens": 8192,
            "stream": true,
            "temperature": 0.7,
        });

        let client = reqwest::Client::new();
        let mut req = client.post(&chat_url)
            .header("Content-Type", "application/json");

        if !api_key.is_empty() && api_key != "ollama-local" && api_key != "llama-swap-local" {
            req = req.header("Authorization", format!("Bearer {}", api_key));
        }

        match req.json(&payload).send().await {
            Ok(response) => {
                let mut stream = response.bytes_stream();
                use futures::StreamExt;
                let mut buffer = String::new();
                let mut in_think: bool = false;

                while let Some(chunk_result) = stream.next().await {
                    match chunk_result {
                        Ok(chunk) => {
                            let chunk_str = String::from_utf8_lossy(&chunk);
                            buffer.push_str(&chunk_str);

                            // Parse SSE lines from buffer
                            while let Some(line_end) = buffer.find('\n') {
                                let line = buffer[..line_end].trim().to_string();
                                buffer = buffer[line_end + 1..].to_string();

                                if line.is_empty() || line.starts_with(':') {
                                    continue;
                                }
                                if line == "data: [DONE]" {
                                    let evt = Event::default().data("[DONE]");
                                    let _ = tx.send(Ok(evt)).await;
                                    return;
                                }
                                if let Some(data) = line.strip_prefix("data: ") {
                                    if let Ok(json) = serde_json::from_str::<serde_json::Value>(data) {
                                        if let Some(choices) = json["choices"].as_array() {
                                            if let Some(choice) = choices.first() {
                                                let content = choice["delta"]["content"].as_str().unwrap_or("");
                                                let raw = if !content.is_empty() { content } else { "" };
                                                // Strip <think>...</think> blocks with cross-chunk state
                                                let delta = strip_think_tags_stream(raw, &mut in_think);
                                                if !delta.is_empty() {
                                                    let evt = Event::default().data(serde_json::json!({"content": delta}).to_string());
                                                    let _ = tx.send(Ok(evt)).await;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Err(e) => {
                            let evt = Event::default().data(serde_json::json!({"error": e.to_string()}).to_string());
                            let _ = tx.send(Ok(evt)).await;
                            break;
                        }
                    }
                }
                let evt = Event::default().data("[DONE]");
                let _ = tx.send(Ok(evt)).await;
            }
            Err(e) => {
                let evt = Event::default().data(serde_json::json!({"error": e.to_string()}).to_string());
                let _ = tx.send(Ok(evt)).await;
                let evt = Event::default().data("[DONE]");
                let _ = tx.send(Ok(evt)).await;
            }
        }
    });

    let stream = ReceiverStream::new(rx);
    Sse::new(stream).keep_alive(
        axum::response::sse::KeepAlive::new()
            .interval(std::time::Duration::from_secs(15))
            .text("keep-alive"),
    )
}

#[derive(Deserialize)]
pub struct SessionsQuery {
    limit: Option<u32>,
}

pub async fn get_sessions(
    Query(query): Query<SessionsQuery>,
) -> Json<serde_json::Value> {
    let limit = query.limit.unwrap_or(20).to_string();
    match run_hermes(&["sessions", "list", "--limit", &limit]) {
        Ok((stdout, _, _)) => {
            let mut sessions = Vec::new();
            for line in stdout.lines().skip(2) {
                let trimmed = line.trim_end();
                if trimmed.is_empty() || trimmed.len() < 88 {
                    continue;
                }
                let title = trimmed[..32].trim().to_string();
                let preview = trimmed[33..73].trim().to_string();
                let last_active = trimmed[74..87].trim().to_string();
                let sid = trimmed[88..].trim().to_string();
                if !sid.is_empty() && !sid.starts_with('─') {
                    sessions.push(serde_json::json!({
                        "id": sid,
                        "title": if title.is_empty() { "Untitled" } else { &title },
                        "preview": preview,
                        "last_active": last_active,
                    }));
                }
            }
            Json(serde_json::json!({"sessions": sessions, "count": sessions.len()}))
        }
        Err(stderr) => Json(serde_json::json!({"sessions": [], "error": stderr})),
    }
}

#[derive(Deserialize)]
pub struct LogsQuery {
    lines: Option<u32>,
    level: Option<String>,
}

pub async fn get_logs(
    State(state): State<Arc<AppState>>,
    Query(query): Query<LogsQuery>,
) -> Json<serde_json::Value> {
    let lines_count = query.lines.unwrap_or(50) as usize;
    let level = query.level.as_deref().unwrap_or("all");

    match run_hermes(&["logs", "--level", level]) {
        Ok((stdout, _, _)) => {
            let mut entries = Vec::new();
            let log_lines: Vec<&str> = stdout.lines().collect();
            for line in log_lines.iter().rev().take(lines_count).rev() {
                let line = line.trim();
                if line.is_empty() {
                    continue;
                }
                let (ts, lvl, msg) = parse_log_line(line);
                entries.push(serde_json::json!({
                    "timestamp": ts,
                    "level": lvl,
                    "message": msg,
                }));
            }
            Json(serde_json::json!({"entries": entries, "count": entries.len()}))
        }
        _ => {
            match read_file(&state.agent_log()) {
                Ok(content) => {
                    let mut entries = Vec::new();
                    let log_lines: Vec<&str> = content.lines().collect();
                    for line in log_lines.iter().rev().take(lines_count).rev() {
                        let (ts, lvl, msg) = parse_log_line(line);
                        entries.push(serde_json::json!({
                            "timestamp": ts,
                            "level": lvl,
                            "message": msg,
                        }));
                    }
                    Json(serde_json::json!({"entries": entries, "count": entries.len()}))
                }
                Err(e) => Json(serde_json::json!({"entries": [], "error": e})),
            }
        }
    }
}

pub fn parse_log_line(line: &str) -> (String, String, String) {
    let re = regex::Regex::new(r"(\d{4}-\d{2}-\d{2}[\sT]\d{2}:\d{2}:\d{2})").unwrap();
    let ts = re
        .captures(line)
        .and_then(|c| c.get(1))
        .map(|m| m.as_str().to_string())
        .unwrap_or_default();

    let after_ts = if ts.is_empty() {
        line
    } else {
        line[ts.len()..].trim()
    };

    let level_re = regex::Regex::new(r"\[(INFO|WARNING|ERROR|DEBUG|CRITICAL)\]").unwrap();
    if let Some(caps) = level_re.captures(after_ts) {
        let lvl = caps.get(1).unwrap().as_str().to_string();
        let msg = after_ts[caps.get(0).unwrap().end()..].trim().to_string();
        (ts, lvl, msg)
    } else {
        (ts, "INFO".into(), after_ts.to_string())
    }
}

