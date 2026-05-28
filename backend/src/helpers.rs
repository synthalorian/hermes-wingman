use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::time::Duration;
use std::net::TcpStream;
use crate::platform::{hermes_home_dir, run_hermes};
use crate::state::AppState;
use serde::{Serialize, Deserialize};

// ── Helpers ────────────────────────────────────────────────────────────────

pub fn read_file(path: &PathBuf) -> Result<String, String> {
    std::fs::read_to_string(path).map_err(|e| format!("Failed to read {}: {}", path.display(), e))
}

pub fn read_config() -> serde_yaml::Value {
    let config_path = hermes_home_dir().join("config.yaml");
    let raw = read_file(&config_path).unwrap_or_default();
    serde_yaml::from_str(&raw).unwrap_or(serde_yaml::Value::Null)
}

/// Load SOUL.md identity from ~/.hermes/SOUL.md
/// Returns empty string if not found.
pub fn load_soul_md() -> String {
    let soul_path = hermes_home_dir().join("SOUL.md");
    match read_file(&soul_path) {
        Ok(content) => {
            let trimmed = content.trim().to_string();
            eprintln!("[Hermes Wingman] Loaded SOUL.md ({} chars) from {}", trimmed.len(), soul_path.display());
            trimmed
        }
        Err(e) => {
            eprintln!("[Hermes Wingman] No SOUL.md found at {}: {}", soul_path.display(), e);
            String::new()
        }
    }
}

/// Read ~/.hermes/auth.json and return the set of provider names that use OAuth.
/// These providers MUST be routed through the Hermes CLI — direct HTTP calls
/// will fail with 401 because the CLI manages token refresh natively.
pub fn oauth_providers() -> HashSet<String> {
    let auth_path = hermes_home_dir().join("auth.json");
    match read_file(&auth_path) {
        Ok(content) => {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                let mut providers = HashSet::new();
                if let Some(provs) = json["providers"].as_object() {
                    for (name, _cfg) in provs {
                        providers.insert(name.clone());
                    }
                }
                providers
            } else {
                HashSet::new()
            }
        }
        Err(_) => HashSet::new(),
    }
}

/// Build the messages array with SOUL.md identity prepended and optional session history.
/// Returns `[{"role": "system", "content": "<SOUL.md>"}, ..., {"role": "user", "content": <message>}]`
/// if SOUL.md exists, or just `[{"role": "user", "content": <message>}]` if not.
/// When session_id is provided, loads session history and injects it as additional system context.
pub fn build_chat_messages(message: &str, session_id: Option<&str>) -> Vec<serde_json::Value> {
    let soul_content = load_soul_md();
    let mut messages: Vec<serde_json::Value> = Vec::new();

    if !soul_content.is_empty() {
        messages.push(serde_json::json!({"role": "system", "content": soul_content}));
    }

    // Inject session history if resuming
    if let Some(sid) = session_id {
        if !sid.is_empty() {
            if let Ok((hist, _, _)) = run_hermes(&["sessions", "get", sid]) {
                let trimmed = hist.trim();
                if !trimmed.is_empty() {
                    messages.push(serde_json::json!({"role": "system", "content": trimmed}));
                }
            }
        }
    }

    messages.push(serde_json::json!({"role": "user", "content": message}));
    messages
}

/// Get the currently active model — checks Wingman's in-memory override first,
/// then falls back to config.yaml's `model:` setting.
pub fn get_active_model(state: &AppState) -> String {
    // Check in-memory override first (set by Wingman's model switcher)
    if let Ok(lock) = state.override_model.lock() {
        if let Some(ref model) = *lock {
            return model.clone();
        }
    }
    // Fall back to config.yaml
    let config = read_config();
    config["model"].as_str()
        .map(|s| s.to_string())
        .or_else(|| config["model"]["default"].as_str().map(|s| s.to_string()))
        .unwrap_or_default()
}

/// Provider type classification based on config fields
#[derive(Debug, Clone, PartialEq)]
pub enum ProviderType {
    Ollama,      // localhost:11434
    LlamaSwap,   // localhost:8080
    CloudApiKey, // has api_key or api_key_env
    CloudOAuth,  // has oauth or name ends in -oauth
    Unknown,
}

/// Universal cloud model catalog — ALL major providers with their models.
/// Every model listed here is available to any Hermes user if they configure the provider.
pub fn universal_cloud_catalog() -> Vec<(&'static str, &'static str, &'static str)> {
    vec![
        // xAI Grok
        ("x-ai", "grok-4", "xai"),
        ("x-ai", "grok-4.3", "xai"),
        ("x-ai", "grok-4-mini", "xai"),
        ("x-ai", "grok-4-vision", "xai"),
        ("x-ai", "grok-3", "xai"),
        // Google Gemini
        ("google", "gemini-2.5-flash", "gemini"),
        ("google", "gemini-2.5-pro", "gemini"),
        ("google", "gemini-2.0-flash", "gemini"),
        ("google", "gemini-2.0-pro", "gemini"),
        ("google", "gemini-2.0-flash-lite", "gemini"),
        // Anthropic Claude
        ("anthropic", "claude-sonnet-4", "anthropic"),
        ("anthropic", "claude-sonnet-4-20250514", "anthropic"),
        ("anthropic", "claude-opus-4", "anthropic"),
        ("anthropic", "claude-haiku-3.5", "anthropic"),
        ("anthropic", "claude-sonnet-4.5", "anthropic"),
        // OpenAI
        ("openai", "gpt-4o", "openai"),
        ("openai", "gpt-4o-mini", "openai"),
        ("openai", "o3", "openai"),
        ("openai", "o4-mini", "openai"),
        ("openai", "gpt-4.1", "openai"),
        ("openai", "gpt-4.1-mini", "openai"),
        ("openai", "gpt-4.1-nano", "openai"),
        // DeepSeek / Nous
        ("deepseek", "deepseek-v4-flash", "nous"),
        ("deepseek", "deepseek-v3", "nous"),
        ("deepseek", "deepseek-r1", "nous"),
        ("deepseek", "deepseek-v4", "nous"),
        // Meta Llama
        ("meta-llama", "llama-4-scout", "meta-llama"),
        ("meta-llama", "llama-4-maverick", "meta-llama"),
        ("meta-llama", "llama-3.3-70b", "meta-llama"),
        ("meta-llama", "llama-3.2-90b", "meta-llama"),
        ("meta-llama", "llama-3.1-405b", "meta-llama"),
        // Mistral
        ("mistral", "mistral-large", "mistral"),
        ("mistral", "mistral-small", "mistral"),
        ("mistral", "mistral-codestral", "mistral"),
        ("mistral", "ministral-8b", "mistral"),
        // Qwen
        ("qwen", "qwen-3-235b-a22b", "qwen"),
        ("qwen", "qwen-3-30b-a3b", "qwen"),
        ("qwen", "qwen-3-235b", "qwen"),
        ("qwen", "qwen-3-30b", "qwen"),
        ("qwen", "qwen-2.5-72b", "qwen"),
    ]
}

pub fn classify_provider(name: &str, cfg: &serde_yaml::Value) -> ProviderType {
    let base_url = cfg["base_url"].as_str().unwrap_or("");
    if base_url.contains("localhost:8080") || base_url.contains("127.0.0.1:8080") {
        return ProviderType::LlamaSwap;
    }
    if base_url.contains("localhost:11434") || base_url.contains("127.0.0.1:11434") {
        return ProviderType::Ollama;
    }
    if name.ends_with("-oauth") || cfg["oauth"].is_mapping() || cfg["auth_type"].as_str() == Some("oauth") {
        return ProviderType::CloudOAuth;
    }
    if cfg["api_key"].is_string() || cfg["api_key_env"].is_string() {
        return ProviderType::CloudApiKey;
    }
    ProviderType::Unknown
}

