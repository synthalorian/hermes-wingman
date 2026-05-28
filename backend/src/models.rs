use std::collections::HashSet;
use serde::Serialize;
use crate::helpers::{read_config, read_file, oauth_providers, universal_cloud_catalog, classify_provider, ProviderType};
use crate::platform::{hermes_home_dir, run_hermes};

// ── Models ─────────────────────────────────────────────────────────────────

#[derive(Serialize)]
pub struct ModelEntry {
    name: String,
    source: String,  // "local", "fallback", "cloud"
    provider_name: String,
}

#[derive(Serialize)]
pub struct ModelsResponse {
    local: Vec<ModelEntry>,
    cloud: Vec<ModelEntry>,
    fallback: Vec<String>,
    current: String,
    provider: String,
}

pub async fn discover_models() -> ModelsResponse {
    let config = read_config();

    // model in config can be either "model: string" or "model: {default: string}"
    let current = config["model"].as_str()
        .map(|s| s.to_string())
        .or_else(|| config["model"]["default"].as_str().map(|s| s.to_string()))
        .unwrap_or_default();

    let current_provider = config["model"]["provider"]
        .as_str()
        .unwrap_or("")
        .to_string();

    // Parse providers from config
    let providers_map = config["providers"].as_mapping().cloned().unwrap_or_default();

    // Local models from llama-swap
    let mut local: Vec<ModelEntry> = Vec::new();
    if let Ok(output) = std::process::Command::new("curl")
        .args(["-s", "--max-time", "3", "http://127.0.0.1:8080/v1/models"])
        .output()
    {
        if let Ok(body) = serde_json::from_slice::<serde_json::Value>(&output.stdout) {
            if let Some(data) = body["data"].as_array() {
                for m in data {
                    if let Some(id) = m["id"].as_str() {
                        local.push(ModelEntry {
                            name: format!("llama-swap/{}", id),
                            source: "local".into(),
                            provider_name: "llama-swap".into(),
                        });
                    }
                }
            }
        }
    }

    // Fallback models from config
    let mut fallback: Vec<String> = Vec::new();
    if let Some(fb) = config["fallback_providers"].as_sequence() {
        for item in fb {
            if let Some(name) = item.as_str() {
                fallback.push(name.to_string());
            }
        }
    }

    // Mark fallback items in local as fallback source
    for fb in &fallback {
        for m in local.iter_mut() {
            if m.name == *fb {
                m.source = "fallback".into();
            }
        }
    }

    // Cloud models: discover from providers in config, then universal catalog
    let catalog = universal_cloud_catalog();
    let mut seen_cloud = HashSet::new();
    let mut cloud: Vec<ModelEntry> = Vec::new();

    // Build set of configured provider types for tagging
    let configured_providers: HashSet<String> = providers_map.keys()
        .filter_map(|k| k.as_str().map(|s| s.to_string()))
        .collect();

    // Step 1: Add all universal catalog models
    for (prefix, model_name, _provider_group) in &catalog {
        let full_name = format!("{}/{}", prefix, model_name);
        if seen_cloud.insert(full_name.clone()) {
            // Determine source: "configured" if the user has a provider for this, "available" otherwise
            let is_configured = configured_providers.iter().any(|p| {
                p == prefix
                || (prefix == &"google" && (p == "gemini" || p == "gemini-oauth"))
                || (prefix == &"x-ai" && (p.contains("xai") || p.contains("grok")))
                || (prefix == &"deepseek" && (p == "nous" || p == "deepseek"))
                || (prefix == &"anthropic" && (p == "claude" || p.starts_with("anthropic")))
                || (prefix == &"openai" && p.starts_with("openai"))
                || (prefix == &"meta-llama" && (p.starts_with("meta-llama") || p.starts_with("llama")))
                || (prefix == &"mistral" && p.starts_with("mistral"))
                || (prefix == &"qwen" && p.starts_with("qwen"))
            });

            cloud.push(ModelEntry {
                name: full_name,
                source: if is_configured { "configured".into() } else { "available".into() },
                provider_name: prefix.to_string(),
            });
        }
    }

    // Also add fallback models to cloud if they're not local
    for fb in &fallback {
        if !seen_cloud.contains(fb) && !local.iter().any(|m| m.name == *fb) {
            cloud.push(ModelEntry {
                name: fb.clone(),
                source: "cloud".into(),
                provider_name: fb.split('/').next().unwrap_or("").to_string(),
            });
        }
    }

    // If no providers in config, fall back to hardcoded defaults
    if cloud.is_empty() {
        let defaults = vec![
            ("deepseek/deepseek-v4-flash", "deepseek"),
            ("deepseek/deepseek-v3", "deepseek"),
            ("anthropic/claude-sonnet-4", "anthropic"),
            ("anthropic/claude-haiku-3.5", "anthropic"),
            ("google/gemini-2.5-flash", "google"),
            ("google/gemini-2.5-pro", "google"),
            ("x-ai/grok-4.3", "xai"),
            ("x-ai/grok-4-mini", "xai"),
            ("openai/gpt-4o", "openai"),
            ("openai/gpt-4o-mini", "openai"),
        ];
        for (name, _prov) in defaults {
            if seen_cloud.insert(name.to_string()) {
                cloud.push(ModelEntry {
                    name: name.to_string(),
                    source: "cloud".into(),
                    provider_name: name.split('/').next().unwrap_or("").to_string(),
                });
            }
        }
    }

    ModelsResponse { local, cloud, fallback, current, provider: current_provider }
}

pub fn probe_model_via_curl(model_name: &str, config: &serde_yaml::Value) -> (String, String) {
    // Determine which provider handles this model
    let prefix = model_name.split('/').next().unwrap_or("");
    let model_short = model_name.split('/').last().unwrap_or(model_name);

    // Map model prefix to config provider name
    let config_provider = match prefix {
        "x-ai" => {
            // Find xai-oauth provider first, then xai
            if let Some(providers) = config["providers"].as_mapping() {
                for (name, _) in providers {
                    let n = name.as_str().unwrap_or("");
                    if n.contains("xai") || n.contains("grok") {
                        return probe_via_provider(config, n, model_short, model_name);
                    }
                }
            }
            "xai-oauth"
        }
        "google" => {
            if let Some(providers) = config["providers"].as_mapping() {
                for (name, _) in providers {
                    let n = name.as_str().unwrap_or("");
                    if n == "gemini-oauth" || n == "gemini" {
                        return probe_via_provider(config, n, model_short, model_name);
                    }
                }
            }
            "gemini"
        }
        "llama-swap" => "llama-swap",
        "deepseek" => {
            // Try nous first, then deepseek
            if let Some(providers) = config["providers"].as_mapping() {
                for (name, _) in providers {
                    let n = name.as_str().unwrap_or("");
                    if n == "nous" || n == "deepseek" {
                        return probe_via_provider(config, n, model_short, model_name);
                    }
                }
            }
            "nous"
        }
        "anthropic" | "claude" => "anthropic",
        "openai" => "openai",
        "meta-llama" | "llama" => "openai",
        "mistral" => "mistral",
        "qwen" => "qwen",
        _ => prefix,
    };

    if config_provider == "llama-swap" || config_provider == "ollama" {
        return probe_via_provider(config, config_provider, model_short, model_name);
    }

    probe_via_provider(config, config_provider, model_short, model_name)
}

pub fn probe_via_provider(config: &serde_yaml::Value, provider_name: &str, model: &str, full_name: &str) -> (String, String) {
    let base_url = config["providers"][provider_name]["base_url"]
        .as_str()
        .unwrap_or("")
        .to_string();

    let api_key = config["providers"][provider_name]["api_key"]
        .as_str()
        .map(|s| s.to_string());

    if base_url.is_empty() || oauth_providers().contains(provider_name) {
        // Fallback: try hermes --oneshot
        match run_hermes(&["--model", full_name, "--oneshot", "hi"]) {
            Ok((stdout, _, code)) if code == 0 && !stdout.trim().is_empty() => {
                return ("ok".into(), "".into());
            }
            Ok((_, stderr, _)) => {
                return ("error".into(), stderr.trim().into());
            }
            Err(e) => return ("error".into(), e),
        }
    }

    let chat_url = format!("{}/chat/completions", base_url.trim_end_matches('/'));
    let payload = serde_json::json!({
        "model": model,
        "messages": [{"role": "user", "content": "say hi"}],
        "max_tokens": 20,
        "stream": false,
    });

    let payload_str = serde_json::to_string(&payload).unwrap_or_default();

    let mut curl = std::process::Command::new("curl");
    curl.args(["-s", "--max-time", "30", "-X", "POST", &chat_url,
               "-H", "Content-Type: application/json",
               "-d", &payload_str]);

    if let Some(key) = &api_key {
        if !key.is_empty() && key != "ollama-local" && key != "llama-swap-local" {
            curl.arg("-H");
            curl.arg(format!("Authorization: Bearer {}", key));
        }
    }

    match curl.output() {
        Ok(output) => {
            if !output.status.success() {
                // Read error body, might contain useful info
                let body = String::from_utf8_lossy(&output.stdout).to_string();
                let err_msg = if !body.is_empty() {
                    // Truncate to first meaningful line
                    body.lines().next().unwrap_or(&body).chars().take(150).collect::<String>()
                } else {
                    format!("HTTP {}", output.status)
                };
                return ("error".into(), err_msg);
            }
            // Parse response body to check for actual content
            let body = String::from_utf8_lossy(&output.stdout);
            match serde_json::from_str::<serde_json::Value>(&body) {
                Ok(json) => {
                    let empty_vec = vec![];
                    let choices = json["choices"].as_array().unwrap_or(&empty_vec);
                    if choices.is_empty() {
                        return ("error".into(), "no choices in response".into());
                    }
                    let msg = &choices[0]["message"];
                    let content = msg["content"].as_str().unwrap_or("");
                    let reasoning = msg["reasoning_content"].as_str().unwrap_or("");
                    if !content.is_empty() || !reasoning.is_empty() {
                        ("ok".into(), "".into())
                    } else {
                        ("error".into(), "empty response (model may need more tokens or is still loading)".into())
                    }
                }
                Err(_) => {
                    // Response wasn't JSON — show raw error from provider
                    let snippet = body.chars().take(200).collect::<String>();
                    ("error".into(), snippet)
                }
            }
        }
        Err(e) => ("error".into(), e.to_string()),
    }
}

