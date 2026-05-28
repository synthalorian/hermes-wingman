use serde::{Deserialize, Serialize};
use crate::helpers::{read_config, load_soul_md, oauth_providers};
use crate::platform::run_hermes;

// ─── Chat ──────────────────────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct ChatRequest {
    message: String,
    session_id: Option<String>,
}

#[derive(Serialize)]
pub struct ChatResponse {
    response: String,
    session_id: Option<String>,
    success: bool,
    error: Option<String>,
}

pub fn handle_chat(req: ChatRequest, current_model_override: &str) -> ChatResponse {
    // Try direct API call to current model first
    let config = read_config();
    let current_model = if !current_model_override.is_empty() {
        current_model_override
    } else {
        config["model"].as_str()
            .or_else(|| config["model"]["default"].as_str())
            .unwrap_or("")
    };

    if !current_model.is_empty() {
        // Determine provider for this model
        let prefix = current_model.split('/').next().unwrap_or("");
        let model_short = current_model.split('/').last().unwrap_or(current_model);
        
        // Find the provider config for this model prefix
        let provider_name = match prefix {
            "x-ai" | "xai" | "grok" => {
                // Find xai-oauth or similar provider in config
                let mut found = "xai-oauth";
                if let Some(providers) = config["providers"].as_mapping() {
                    for (name, _) in providers {
                        let n = name.as_str().unwrap_or("");
                        if n.contains("xai") || n.contains("grok") {
                            found = n;
                            break;
                        }
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

        let base_url = config["providers"][provider_name]["base_url"]
            .as_str()
            .unwrap_or("")
            .to_string();
        let api_key = config["providers"][provider_name]["api_key"]
            .as_str()
            .map(|s| s.to_string());

        if !base_url.is_empty() && !oauth_providers().contains(provider_name) {
            let chat_url = format!("{}/chat/completions", base_url.trim_end_matches('/'));

            // Build messages with SOUL.md identity + resume context
            let soul_content = load_soul_md();
            let mut messages: Vec<serde_json::Value> = Vec::new();

            // Inject SOUL.md identity first (if available)
            if !soul_content.is_empty() {
                messages.push(serde_json::json!({"role": "system", "content": soul_content}));
            }

            // Inject resume session context
            if let Some(sid) = &req.session_id {
                if !sid.is_empty() {
                    // Try to get previous messages from session
                    if let Ok((hist, _, _)) = run_hermes(&["sessions", "get", sid]) {
                        if !hist.trim().is_empty() {
                            messages.push(serde_json::json!({"role": "system", "content": hist}));
                        }
                    }
                }
            }

            // Add user message
            messages.push(serde_json::json!({"role": "user", "content": req.message}));

            let payload = serde_json::json!({
                "model": model_short,
                "messages": messages,
                "max_tokens": 2048,
                "stream": false,
                "temperature": 0.7,
            });

            let payload_str = serde_json::to_string(&payload).unwrap_or_default();

            let mut curl = std::process::Command::new("curl");
            curl.args(["-s", "--max-time", "120", "-X", "POST", &chat_url,
                       "-H", "Content-Type: application/json",
                       "-d", &payload_str]);

            if let Some(key) = &api_key {
                if !key.is_empty() && key != "ollama-local" && key != "llama-swap-local" {
            curl.arg("-H");
            curl.arg(format!("Authorization: Bearer {}", key));
                }
            }

            if let Ok(output) = curl.output() {
                if output.status.success() {
                    let body = String::from_utf8_lossy(&output.stdout);
                    if let Ok(json) = serde_json::from_str::<serde_json::Value>(&body) {
                        if let Some(choices) = json["choices"].as_array() {
                            if let Some(choice) = choices.first() {
                                let msg = &choice["message"];
                                let content = msg["content"].as_str().unwrap_or("").to_string();
                                let reasoning = msg["reasoning_content"].as_str().unwrap_or("").to_string();
                                
                                // Use reasoning content if main content is empty
                                let response = if !content.is_empty() {
                                    content
                                } else if !reasoning.is_empty() {
                                    format!("[Thinking process omitted]\n{}", 
                                        if reasoning.len() > 500 {
                                            format!("{}...", &reasoning[..500])
                                        } else {
                                            reasoning
                                        }
                                    )
                                } else {
                                    String::new()
                                };

                                return ChatResponse {
                                    response,
                                    session_id: req.session_id,
                                    success: true,
                                    error: None,
                                };
                            }
                        }
                    }
                }
            }
        }
    }

    // Fallback to hermes CLI
    let mut args = vec!["-z", &req.message];
    if let Some(sid) = &req.session_id {
        if !sid.is_empty() {
            args = vec!["--resume", sid, "-z", &req.message];
        }
    }

    match run_hermes(&args) {
        Ok((stdout, stderr, code)) if code == 0 => {
            let session_id = if stderr.contains("session") {
                let re = regex::Regex::new(r"session[=_ ]([a-zA-Z0-9_]+)").unwrap();
                re.captures(&stderr)
                    .and_then(|c| c.get(1))
                    .map(|m| m.as_str().to_string())
                    .or(req.session_id)
            } else {
                req.session_id
            };

            ChatResponse {
                response: stdout.trim().to_string(),
                session_id,
                success: true,
                error: None,
            }
        }
        Ok((_, stderr, _)) => ChatResponse {
            response: String::new(),
            session_id: None,
            success: false,
            error: Some(stderr.trim().to_string()),
        },
        Err(e) => ChatResponse {
            response: String::new(),
            session_id: None,
            success: false,
            error: Some(e),
        },
    }
}

