use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::{Json, Sse},
    routing::{get, post},
    Router,
};
use futures::stream::Stream;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::PathBuf;
use std::process::Command;
use std::sync::Arc;
use std::sync::Mutex;
use tower_http::cors::CorsLayer;

// ── Platform Helpers ─────────────────────────────────────────────────────────

/// Cross-platform hermes home directory.
/// Linux/macOS: ~/.hermes
/// Windows: %LOCALAPPDATA%\hermes
fn hermes_home_dir() -> PathBuf {
    #[cfg(target_os = "windows")]
    {
        let local = std::env::var("LOCALAPPDATA")
            .or_else(|_| std::env::var("APPDATA"))
            .unwrap_or_else(|_| {
                let profile = std::env::var("USERPROFILE").unwrap_or_else(|_| "C:\\Users\\Default".into());
                format!("{}\\AppData\\Local", profile)
            });
        PathBuf::from(format!("{}\\hermes", local))
    }
    #[cfg(not(target_os = "windows"))]
    {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
        PathBuf::from(format!("{}/.hermes", home))
    }
}

/// Find the `hermes` binary on any platform.
fn find_hermes_binary() -> Option<String> {
    #[cfg(target_os = "windows")]
    let which_cmd = "where";
    #[cfg(not(target_os = "windows"))]
    let which_cmd = "which";

    // Try which/where command first (works on any platform when on PATH)
    let from_path = std::process::Command::new(which_cmd)
        .arg("hermes")
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                String::from_utf8(o.stdout).ok()
                    .map(|s| s.lines().next().unwrap_or("").trim().to_string())
            } else {
                None
            }
        });
    if from_path.is_some() {
        return from_path;
    }

    // Fallback: common platform-specific paths
    #[cfg(target_os = "windows")]
    {
        let local = std::env::var("LOCALAPPDATA").unwrap_or_else(|_| "C:\\Users\\Default\\AppData\\Local".into());
        let paths = vec![
            format!("{}\\hermes\\hermes.exe", local),
            format!("{}\\hermes\\Scripts\\hermes.exe", local),
            format!("{}\\Python\\Scripts\\hermes.exe", local),
            "C:\\Program Files\\hermes\\hermes.exe".into(),
        ];
        paths.iter().find(|p| std::path::Path::new(p).exists()).cloned()
    }
    #[cfg(not(target_os = "windows"))]
    {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
        let paths = vec![
            format!("{}/.local/bin/hermes", home),
            "/usr/bin/hermes".into(),
            "/usr/local/bin/hermes".into(),
            "/opt/homebrew/bin/hermes".into(),
            format!("/Users/{}/.local/bin/hermes", home.split('/').last().unwrap_or("")),
        ];
        paths.iter().find(|p| std::path::Path::new(p).exists()).cloned()
    }
}

/// Run `hermes` CLI command (platform-agnostic)
fn run_hermes(args: &[&str]) -> Result<(String, String, i32), String> {
    let output = Command::new("hermes")
        .args(args)
        .env("PAGER", "cat")
        .output()
        .map_err(|e| format!("Failed to run hermes: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    Ok((stdout, stderr, output.status.code().unwrap_or(-1)))
}

// ── State ─────────────────────────────────────────────────────────────────

#[derive(Clone)]
struct AppState {
    hermes_home: PathBuf,
    /// In-memory model override — set by Wingman's model switcher.
    /// When Some, all chat requests use this model instead of config.yaml's `model:`.
    /// When None, falls back to config.yaml.
    override_model: Arc<Mutex<Option<String>>>,
}

impl AppState {
    fn new() -> Self {
        Self {
            hermes_home: hermes_home_dir(),
            override_model: Arc::new(Mutex::new(None)),
        }
    }

    fn config_path(&self) -> PathBuf {
        self.hermes_home.join("config.yaml")
    }

    fn gateway_state_path(&self) -> PathBuf {
        self.hermes_home.join("gateway_state.json")
    }

    fn logs_dir(&self) -> PathBuf {
        self.hermes_home.join("logs")
    }

    fn agent_log(&self) -> PathBuf {
        self.logs_dir().join("agent.log")
    }
}

// ── Helpers ────────────────────────────────────────────────────────────────

fn read_file(path: &PathBuf) -> Result<String, String> {
    std::fs::read_to_string(path).map_err(|e| format!("Failed to read {}: {}", path.display(), e))
}

fn read_config() -> serde_yaml::Value {
    let config_path = hermes_home_dir().join("config.yaml");
    let raw = read_file(&config_path).unwrap_or_default();
    serde_yaml::from_str(&raw).unwrap_or(serde_yaml::Value::Null)
}

/// Load SOUL.md identity from ~/.hermes/SOUL.md
/// Returns empty string if not found.
fn load_soul_md() -> String {
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
fn oauth_providers() -> HashSet<String> {
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
fn build_chat_messages(message: &str, session_id: Option<&str>) -> Vec<serde_json::Value> {
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
fn get_active_model(state: &AppState) -> String {
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
enum ProviderType {
    Ollama,      // localhost:11434
    LlamaSwap,   // localhost:8080
    CloudApiKey, // has api_key or api_key_env
    CloudOAuth,  // has oauth or name ends in -oauth
    Unknown,
}

/// Universal cloud model catalog — ALL major providers with their models.
/// Every model listed here is available to any Hermes user if they configure the provider.
fn universal_cloud_catalog() -> Vec<(&'static str, &'static str, &'static str)> {
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

fn classify_provider(name: &str, cfg: &serde_yaml::Value) -> ProviderType {
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

// ── Models ─────────────────────────────────────────────────────────────────

#[derive(Serialize)]
struct ModelEntry {
    name: String,
    source: String,  // "local", "fallback", "cloud"
    provider_name: String,
}

#[derive(Serialize)]
struct ModelsResponse {
    local: Vec<ModelEntry>,
    cloud: Vec<ModelEntry>,
    fallback: Vec<String>,
    current: String,
    provider: String,
}

async fn discover_models() -> ModelsResponse {
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

fn probe_model_via_curl(model_name: &str, config: &serde_yaml::Value) -> (String, String) {
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

fn probe_via_provider(config: &serde_yaml::Value, provider_name: &str, model: &str, full_name: &str) -> (String, String) {
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

// ─── Chat ──────────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct ChatRequest {
    message: String,
    session_id: Option<String>,
}

#[derive(Serialize)]
struct ChatResponse {
    response: String,
    session_id: Option<String>,
    success: bool,
    error: Option<String>,
}

fn handle_chat(req: ChatRequest, current_model_override: &str) -> ChatResponse {
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

// ── HTTP Handlers ──────────────────────────────────────────────────────────

async fn health(State(_state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    let hermes_check = Command::new("hermes")
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

async fn get_config(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
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

async fn write_config(
    State(state): State<Arc<AppState>>,
    Json(body): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let content = body["content"].as_str().ok_or(StatusCode::BAD_REQUEST)?;
    std::fs::write(&state.config_path(), content).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(serde_json::json!({"success": true})))
}

async fn update_config(
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

async fn get_models(State(state): State<Arc<AppState>>) -> Json<ModelsResponse> {
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

async fn switch_model(
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

async fn probe_model_handler(
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

async fn chat_handler(
    State(state): State<Arc<AppState>>,
    Json(body): Json<ChatRequest>,
) -> Json<ChatResponse> {
    let current_model = get_active_model(&state);
    Json(handle_chat(body, &current_model))
}

#[derive(Deserialize)]
struct SessionsQuery {
    limit: Option<u32>,
}

// ── Chat Streaming (SSE) ─────────────────────────────────────────────────

#[derive(Deserialize)]
struct ChatStreamQuery {
    message: String,
    session_id: Option<String>,
}

async fn chat_stream_handler(
    State(state): State<Arc<AppState>>,
    Query(query): Query<ChatStreamQuery>,
) -> Sse<impl Stream<Item = Result<axum::response::sse::Event, std::convert::Infallible>>> {
    use std::convert::Infallible;
    use axum::response::sse::Event;
    use tokio::sync::mpsc;
    use tokio_stream::wrappers::ReceiverStream;

    let (tx, rx) = mpsc::channel::<Result<Event, Infallible>>(32);
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
            // Fallback to hermes CLI
            let mut args = vec!["-z", &message];
            if let Some(sid) = &session_id {
                if !sid.is_empty() {
                    args = vec!["--resume", sid, "-z", &message];
                }
            }
            match std::process::Command::new("hermes").args(&args).output() {
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

async fn get_sessions(
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
struct LogsQuery {
    lines: Option<u32>,
    level: Option<String>,
}

async fn get_logs(
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

fn parse_log_line(line: &str) -> (String, String, String) {
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

async fn get_gateway(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    let gw_path = state.gateway_state_path();
    match read_file(&gw_path) {
        Ok(content) => {
            match serde_json::from_str::<serde_json::Value>(&content) {
                Ok(json) => {
                    let is_running = json["gateway_state"].as_str() == Some("running");
                    let platforms: Vec<serde_json::Value> = json["platforms"]
                        .as_object()
                        .map(|obj| {
                            obj.iter()
                                .map(|(name, info)| {
                                    let state = info["state"].as_str().unwrap_or("disconnected");
                                    serde_json::json!({
                                        "name": name,
                                        "state": state,
                                        "isConnected": state == "connected",
                                        "error": info["error_message"],
                                    })
                                })
                                .collect()
                        })
                        .unwrap_or_default();

                    Json(serde_json::json!({
                        "running": is_running,
                        "pid": json["pid"],
                        "platforms": platforms,
                    }))
                }
                Err(e) => Json(serde_json::json!({"running": false, "platforms": [], "error": e.to_string()})),
            }
        }
        Err(_) => Json(serde_json::json!({"running": false, "platforms": []})),
    }
}

async fn gateway_toggle(
    State(_state): State<Arc<AppState>>,
    Json(body): Json<serde_json::Value>,
) -> Json<serde_json::Value> {
    let action = body["action"].as_str().unwrap_or("toggle");

    match action {
        "start" => {
            // Start doesn't need confirmation
            match run_hermes(&["gateway", "start"]) {
                Ok((_, _, code)) if code == 0 => {
                    Json(serde_json::json!({"success": true, "action": "start", "running": true}))
                }
                Ok((_, stderr, _)) => {
                    Json(serde_json::json!({"success": false, "action": "start", "error": stderr.trim()}))
                }
                Err(e) => Json(serde_json::json!({"success": false, "action": "start", "error": e})),
            }
        }
        "stop" => {
            // Stop needs confirmation - pipe "y" via stdin
            match std::process::Command::new("hermes")
                .args(["gateway", "stop"])
                .stdin(std::process::Stdio::piped())
                .stdout(std::process::Stdio::piped())
                .stderr(std::process::Stdio::piped())
                .spawn()
            {
                Ok(mut child) => {
                    // Send "y" to stdin for confirmation
                    if let Some(stdin) = child.stdin.take() {
                        use std::io::Write;
                        let _ = write!(&stdin, "y\n");
                        drop(stdin);
                    }
                    match child.wait_with_output() {
                        Ok(output) if output.status.success() => {
                            Json(serde_json::json!({"success": true, "action": "stop", "running": false}))
                        }
                        Ok(output) => {
                            let stderr = String::from_utf8_lossy(&output.stderr).to_string();
                            Json(serde_json::json!({"success": false, "action": "stop", "error": stderr.trim()}))
                        }
                        Err(e) => Json(serde_json::json!({"success": false, "action": "stop", "error": e.to_string()})),
                    }
                }
                Err(e) => Json(serde_json::json!({"success": false, "action": "stop", "error": e.to_string()})),
            }
        }
        _ => Json(serde_json::json!({"error": "unknown action"})),
    }
}

async fn get_cron() -> Json<serde_json::Value> {
    match run_hermes(&["cron", "list"]) {
        Ok((stdout, _, _)) => {
            let jobs: Vec<serde_json::Value> = stdout
                .lines()
                .filter(|l| {
                    let t = l.trim();
                    !t.is_empty()
                        && !t.starts_with("No")
                        && !t.starts_with("Create")
                        && !t.starts_with('─')
                })
                .map(|l| serde_json::json!({"raw": l.trim()}))
                .collect();
            Json(serde_json::json!({"jobs": jobs, "count": jobs.len()}))
        }
        Err(stderr) => Json(serde_json::json!({"jobs": [], "error": stderr})),
    }
}

async fn get_providers(State(_state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    let config = read_config();

    let providers: Vec<serde_json::Value> = config["providers"]
        .as_mapping()
        .map(|map| {
            map.iter()
                .map(|(name, cfg)| {
                    let n = name.as_str().unwrap_or("");
                    let prov_type = format!("{:?}", classify_provider(n, cfg));
                    serde_json::json!({
                        "name": n,
                        "base_url": cfg["base_url"].as_str().unwrap_or(""),
                        "has_api_key": cfg["api_key"].is_string() || cfg["api_key_env"].is_string(),
                        "type": prov_type,
                    })
                })
                .collect()
        })
        .unwrap_or_default();

    Json(serde_json::json!({"providers": providers}))
}

async fn detect_setup(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    let hermes_bin = find_hermes_binary();

    let config = read_config();
    let config_exists = state.config_path().exists();
    let has_api_keys = config["providers"]
        .as_mapping()
        .map(|m| {
            m.values().any(|v| {
                v["api_key"].is_string() || v["api_key_env"].is_string()
            })
        })
        .unwrap_or(false);
    let model_configured = config["model"]["default"].is_string() || config["model"].is_string();

    // Check gateway state for connected platforms
    let gw_platforms: Vec<String> = read_file(&state.gateway_state_path())
        .ok()
        .and_then(|c| serde_json::from_str::<serde_json::Value>(&c).ok())
        .and_then(|j| {
            j["platforms"].as_object().map(|obj| {
                obj.iter()
                    .filter(|(_, info)| info["state"].as_str() == Some("connected"))
                    .map(|(name, _)| name.clone())
                    .collect()
            })
        })
        .unwrap_or_default();

    Json(serde_json::json!({
        "hermes_installed": hermes_bin.is_some(),
        "hermes_bin": hermes_bin,
        "config_exists": config_exists,
        "has_api_keys": has_api_keys,
        "model_configured": model_configured,
        "connected_platforms": gw_platforms,
    }))
}

#[derive(Deserialize)]
struct InstallRequest {
    method: Option<String>,
}

async fn install_hermes(Json(body): Json<InstallRequest>) -> Json<serde_json::Value> {
    let method = body.method.as_deref().unwrap_or("auto");

    match method {
        "brew" => {
            // macOS Homebrew installation
            match Command::new("brew").args(["install", "hermes-agent"]).output() {
                Ok(output) if output.status.success() => {
                    let out = String::from_utf8_lossy(&output.stdout).to_string();
                    Json(serde_json::json!({"success": true, "output": out.chars().take(500).collect::<String>()}))
                }
                Ok(output) => {
                    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
                    Json(serde_json::json!({"success": false, "error": stderr.chars().take(500).collect::<String>()}))
                }
                Err(e) => Json(serde_json::json!({"success": false, "error": format!("Homebrew not found: {}", e)})),
            }
        }
        "pip" | "auto" => {
            // Try pip3 first, then pip
            for pip_cmd in &["pip3", "pip"] {
                if let Ok(output) = Command::new(pip_cmd)
                    .args(["install", "hermes-agent"])
                    .output()
                {
                    if output.status.success() {
                        let out = String::from_utf8_lossy(&output.stdout).to_string();
                        return Json(serde_json::json!({"success": true, "output": out.chars().take(500).collect::<String>()}));
                    }
                    // Check for specific known errors
                    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
                    let err_lower = stderr.to_lowercase();
                    
                    // Detect specific failure modes
                    if err_lower.contains("externally-managed-environment") || err_lower.contains("externally managed") {
                        // Try pip install --break-system-packages
                        if let Ok(retry) = Command::new(pip_cmd)
                            .args(["install", "--break-system-packages", "hermes-agent"])
                            .output()
                        {
                            if retry.status.success() {
                                let out = String::from_utf8_lossy(&retry.stdout).to_string();
                                return Json(serde_json::json!({"success": true, "output": out.chars().take(500).collect::<String>()}));
                            }
                        }
                        return Json(serde_json::json!({
                            "success": false,
                            "error": format!(
                                "Python environment is externally managed on this system.\n\nOptions:\n1. Run: {} install --break-system-packages hermes-agent\n2. Or create a virtual env: python3 -m venv ~/.hermes-venv && ~/.hermes-venv/bin/pip install hermes-agent\n3. Or use pipx: pipx install hermes-agent",
                                pip_cmd
                            )
                        }));
                    }
                    
                    return Json(serde_json::json!({"success": false, "error": stderr.chars().take(500).collect::<String>()}));
                }
            }
            
            // Neither pip3 nor pip found — detect platform and give instructions
            let os_info = detect_os_install_instructions();
            Json(serde_json::json!({
                "success": false,
                "error": format!(
                    "Python/pip not found. Install pip for your system:\n\n{}",
                    os_info
                )
            }))
        }
        _ => Json(serde_json::json!({"success": false, "error": format!("Unknown method: {}", method)})),
    }
}

fn detect_os_install_instructions() -> String {
    // Check for common package managers
    let checks = [
        ("pacman --version", "Arch/Manjaro:  sudo pacman -S python-pip\nThen:  pip3 install hermes-agent"),
        ("apt --version", "Debian/Ubuntu:  sudo apt install python3-pip\nThen:  pip3 install hermes-agent"),
        ("dnf --version", "Fedora/RHEL:  sudo dnf install python3-pip\nThen:  pip3 install hermes-agent"),
        ("brew --version", "macOS:  brew install python\nThen:  pip3 install hermes-agent"),
    ];

    for (cmd, instruction) in &checks {
        if Command::new("sh").args(["-c", cmd]).output().is_ok() {
            return instruction.to_string();
        }
    }

    "Generic Linux:\n  sudo apt install python3-pip  (or use your package manager)\n  pip3 install hermes-agent\n\nOr use a virtual environment:\n  python3 -m venv ~/.hermes-venv\n  ~/.hermes-venv/bin/pip install hermes-agent".to_string()
}

// ─── Auto-Configure ─────────────────────────────────────────────────────────

/// Scan the environment for available providers and generate a config.
async fn auto_configure(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    let mut providers = serde_json::Map::new();
    let mut discovered: Vec<serde_json::Value> = Vec::new();
    let mut fallback_providers: Vec<String> = Vec::new();
    let mut default_model = String::new();

    // 1. Check for llama-swap (localhost:8080)
    let llama_swap_running = check_port(8080);
    if llama_swap_running {
        let llama_provider = serde_json::json!({
            "base_url": "http://127.0.0.1:8080/v1",
            "api_key": "llama-swap-local"
        });
        providers.insert("llama-swap".into(), llama_provider);
        discovered.push(serde_json::json!({
            "name": "llama-swap",
            "type": "local",
            "base_url": "http://127.0.0.1:8080/v1",
            "status": "running"
        }));

        // Auto-discover llama-swap models
        if let Ok(output) = std::process::Command::new("curl")
            .args(["-s", "--max-time", "2", "http://127.0.0.1:8080/v1/models"])
            .output()
        {
            if let Ok(body) = serde_json::from_slice::<serde_json::Value>(&output.stdout) {
                if let Some(data) = body["data"].as_array() {
                    for m in data {
                        if let Some(id) = m["id"].as_str() {
                            let name = format!("llama-swap/{}", id);
                            fallback_providers.push(name);
                        }
                    }
                }
            }
        }
    }

    // 2. Check for Ollama (localhost:11434)
    if check_port(11434) {
        if !providers.contains_key("ollama") {
            providers.insert("ollama".into(), serde_json::json!({
                "base_url": "http://127.0.0.1:11434/v1",
                "api_key": "ollama-local"
            }));
        }
        discovered.push(serde_json::json!({
            "name": "ollama",
            "type": "local",
            "base_url": "http://127.0.0.1:11434/v1",
            "status": "running"
        }));
    }

    // 3. Scan environment variables for API keys
    let env_key_map = vec![
        ("OPENAI_API_KEY", "openai", "https://api.openai.com/v1"),
        ("ANTHROPIC_API_KEY", "anthropic", "https://api.anthropic.com/v1"),
        ("GEMINI_API_KEY", "gemini", "https://generativelanguage.googleapis.com/v1beta"),
        ("GROK_API_KEY", "xai", "https://api.x.ai/v1"),
        ("XAI_API_KEY", "xai", "https://api.x.ai/v1"),
        ("MISTRAL_API_KEY", "mistral", "https://api.mistral.ai/v1"),
        ("DEEPSEEK_API_KEY", "nous", "https://api.nousresearch.com/v1"),
        ("OPENROUTER_API_KEY", "openrouter", "https://openrouter.ai/api/v1"),
        ("TOGETHER_API_KEY", "together", "https://api.together.xyz/v1"),
    ];

    let oauth = oauth_providers();

    for (env_var, provider_name, base_url) in &env_key_map {
        if let Ok(key) = std::env::var(env_var) {
            if !key.is_empty() && !providers.contains_key(*provider_name) && !oauth.contains(*provider_name) {
                providers.insert(provider_name.to_string(), serde_json::json!({
                    "base_url": base_url,
                    "api_key_env": env_var,
                }));
                discovered.push(serde_json::json!({
                    "name": *provider_name,
                    "type": "cloud",
                    "source": format!("env:{}", env_var),
                    "status": "key_found"
                }));
            }
        }
    }

    // 4. Determine default model
    if !fallback_providers.is_empty() {
        default_model = fallback_providers[0].clone();
    } else if !discovered.is_empty() {
        // Pick first cloud provider with a known model
        let cloud_model_map = [
            ("openai", "openai/gpt-4o-mini"),
            ("anthropic", "anthropic/claude-sonnet-4"),
            ("gemini", "google/gemini-2.5-flash"),
            ("xai", "x-ai/grok-4-mini"),
            ("mistral", "mistral/mistral-small"),
            ("nous", "deepseek/deepseek-v4-flash"),
            ("openrouter", "openrouter/openai/gpt-4o-mini"),
        ];
        for (name, model) in &cloud_model_map {
            if discovered.iter().any(|d| d["name"] == *name) {
                default_model = model.to_string();
                break;
            }
        }
    }

    // 5. Read existing config to preserve what's already there
    let existing_raw = read_file(&state.config_path()).unwrap_or_default();
    let existing: serde_yaml::Value = serde_yaml::from_str(&existing_raw).unwrap_or(serde_yaml::Value::Null);

    // 6. Build the new config (merge: don't overwrite existing providers)
    let existing_providers = existing["providers"].as_mapping().cloned().unwrap_or_default();
    for (k, v) in existing_providers {
        let name = k.as_str().unwrap_or("").to_string();
        if !providers.contains_key(&name) {
            providers.insert(name, serde_json::to_value(v).unwrap_or(serde_json::Value::Null));
        }
    }

    // Preserve existing model if set
    let existing_model = existing["model"].as_str()
        .or_else(|| existing["model"]["default"].as_str())
        .unwrap_or("");
    if !existing_model.is_empty() {
        default_model = existing_model.to_string();
    }

    // 7. Write the config — merge with existing to preserve other sections
    let mut config_value = existing.clone();
    
    // Update model
    if let Some(mapping) = config_value.as_mapping_mut() {
        mapping.insert(
            serde_yaml::Value::String("model".into()),
            serde_yaml::Value::String(default_model.clone()),
        );
        
        // Update fallback_providers
        if !fallback_providers.is_empty() {
            let fb_list: Vec<serde_yaml::Value> = fallback_providers.iter()
                .map(|s| serde_yaml::Value::String(s.clone()))
                .collect();
            mapping.insert(
                serde_yaml::Value::String("fallback_providers".into()),
                serde_yaml::Value::Sequence(fb_list),
            );
        }
        
        // Merge providers (don't overwrite existing ones)
        let mut providers_map = serde_yaml::Mapping::new();
        for (name, cfg) in &providers {
            let mut prov = serde_yaml::Mapping::new();
            if let Some(url) = cfg["base_url"].as_str() {
                prov.insert(
                    serde_yaml::Value::String("base_url".into()),
                    serde_yaml::Value::String(url.into()),
                );
            }
            if let Some(key) = cfg["api_key"].as_str() {
                prov.insert(
                    serde_yaml::Value::String("api_key".into()),
                    serde_yaml::Value::String(key.into()),
                );
            }
            if let Some(env) = cfg["api_key_env"].as_str() {
                prov.insert(
                    serde_yaml::Value::String("api_key_env".into()),
                    serde_yaml::Value::String(env.into()),
                );
            }
            providers_map.insert(
                serde_yaml::Value::String(name.clone()),
                serde_yaml::Value::Mapping(prov),
            );
        }
        
        // Merge with existing providers (existing takes precedence)
        if let Some(existing_provs) = mapping.get(&serde_yaml::Value::String("providers".into())) {
            if let Some(existing_map) = existing_provs.as_mapping() {
                for (k, v) in existing_map {
                    providers_map.insert(k.clone(), v.clone());
                }
            }
        }
        
        mapping.insert(
            serde_yaml::Value::String("providers".into()),
            serde_yaml::Value::Mapping(providers_map),
        );
    }
    
    // Serialize to YAML string
    let config_yaml = serde_yaml::to_string(&config_value)
        .unwrap_or_else(|_| format!("model: {}", default_model));
    
    let _ = std::fs::write(&state.config_path(), &config_yaml);

    Json(serde_json::json!({
        "success": true,
        "config_written": true,
        "default_model": default_model,
        "discovered": discovered,
        "providers_count": providers.len(),
        "fallback_count": fallback_providers.len(),
    }))
}

/// Quick TCP port check
fn check_port(port: u16) -> bool {
    use std::net::TcpStream;
    TcpStream::connect_timeout(
        &format!("127.0.0.1:{}", port).parse().unwrap(),
        std::time::Duration::from_millis(500),
    ).is_ok()
}

/// Strip <think>...</think> reasoning tags from model output.
fn strip_think_tags_stream(s: &str, in_think: &mut bool) -> String {
    let mut result = String::with_capacity(s.len());
    let chars: Vec<char> = s.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        if !*in_think && i + 6 < chars.len()
            && chars[i] == '<' && chars[i+1] == 't' && chars[i+2] == 'h'
            && chars[i+3] == 'i' && chars[i+4] == 'n' && chars[i+5] == 'k'
            && chars[i+6] == '>'
        {
            *in_think = true;
            i += 7;
            continue;
        }
        if *in_think && i + 7 < chars.len()
            && chars[i] == '<' && chars[i+1] == '/' && chars[i+2] == 't'
            && chars[i+3] == 'h' && chars[i+4] == 'i' && chars[i+5] == 'n'
            && chars[i+6] == 'k' && chars[i+7] == '>'
        {
            *in_think = false;
            i += 8;
            continue;
        }
        // Also strip orphan </think> tags (no matching opening tag)
        if !*in_think && i + 7 < chars.len()
            && chars[i] == '<' && chars[i+1] == '/' && chars[i+2] == 't'
            && chars[i+3] == 'h' && chars[i+4] == 'i' && chars[i+5] == 'n'
            && chars[i+6] == 'k' && chars[i+7] == '>'
        {
            i += 8;
            continue;
        }
        if !*in_think {
            result.push(chars[i]);
        }
        i += 1;
    }
    result
}

/// Probe a provider by sending a tiny test request
async fn probe_provider_handler(
    Json(body): Json<serde_json::Value>,
) -> Json<serde_json::Value> {
    let provider_name = body["provider"].as_str().unwrap_or("");
    let model = body["model"].as_str().unwrap_or("");

    if provider_name.is_empty() {
        return Json(serde_json::json!({"success": false, "error": "provider name required"}));
    }

    let config = read_config();
    let provider_cfg = &config["providers"][provider_name];
    let base_url = provider_cfg["base_url"].as_str().unwrap_or("");

    if base_url.is_empty() {
        if oauth_providers().contains(provider_name) {
            // OAuth provider without config entry — probe via CLI
            let test_model = if model.is_empty() {
                "deepseek-v4-flash"
            } else {
                &model
            };
            let full_name = format!("deepseek/{}", test_model);
            match run_hermes(&["--model", &full_name, "--oneshot", "hi"]) {
                Ok((stdout, _, code)) if code == 0 && !stdout.trim().is_empty() => {
                    return Json(serde_json::json!({"success": true, "provider": provider_name, "model": test_model}));
                }
                Ok((_, stderr, _)) => {
                    return Json(serde_json::json!({"success": false, "error": stderr.trim(), "provider": provider_name}));
                }
                Err(e) => {
                    return Json(serde_json::json!({"success": false, "error": e, "provider": provider_name}));
                }
            }
        }
        return Json(serde_json::json!({"success": false, "error": "no base_url for provider", "provider": provider_name}));
    }

    let test_model = if model.is_empty() {
        // Try to guess a model name for this provider
        match provider_name {
            "openai" => "gpt-4o-mini",
            "anthropic" => "claude-sonnet-4",
            "gemini" => "gemini-2.5-flash",
            "xai" | "xai-oauth" => "grok-4-mini",
            "mistral" => "mistral-small",
            "nous" | "deepseek" => "deepseek-v4-flash",
            "llama-swap" | "ollama" => "", // local models need explicit name
            _ => "",
        }
    } else {
        model
    };

    if test_model.is_empty() {
        return Json(serde_json::json!({"success": false, "error": "model required for this provider", "provider": provider_name}));
    }

    let chat_url = format!("{}/chat/completions", base_url.trim_end_matches('/'));
    let payload = serde_json::json!({
        "model": test_model,
        "messages": [{"role": "user", "content": "say hi"}],
        "max_tokens": 10,
        "stream": false,
    });

    let payload_str = serde_json::to_string(&payload).unwrap_or_default();
    let api_key = provider_cfg["api_key"].as_str()
        .or_else(|| {
            provider_cfg["api_key_env"].as_str()
                .and_then(|env| std::env::var(env).ok())
                .map(|s| Box::leak(s.into_boxed_str()) as &str)
        })
        .unwrap_or("");

    let mut curl = std::process::Command::new("curl");
    curl.args(["-s", "--max-time", "15", "-X", "POST", &chat_url,
               "-H", "Content-Type: application/json",
               "-d", &payload_str]);

    if !api_key.is_empty() && api_key != "ollama-local" && api_key != "llama-swap-local" {
        curl.arg("-H").arg(format!("Authorization: Bearer {}", api_key));
    }

    match curl.output() {
        Ok(output) => {
            if output.status.success() {
                let body = String::from_utf8_lossy(&output.stdout);
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&body) {
                    let has_content = json["choices"].as_array()
                        .and_then(|c| c.first())
                        .and_then(|c| c["message"]["content"].as_str())
                        .map(|s| !s.is_empty())
                        .unwrap_or(false);
                    if has_content {
                        return Json(serde_json::json!({"success": true, "provider": provider_name, "model": test_model}));
                    }
                }
                // Response but no content — might be auth error
                let snippet = body.chars().take(200).collect::<String>();
                if snippet.contains("401") || snippet.contains("unauthorized") || snippet.contains("Unauthorized") || snippet.contains("auth") {
                    return Json(serde_json::json!({"success": false, "error": "Authentication failed — check your API key", "provider": provider_name}));
                }
                if snippet.contains("429") || snippet.contains("rate") {
                    return Json(serde_json::json!({"success": false, "error": "Rate limited — try again later", "provider": provider_name}));
                }
                return Json(serde_json::json!({"success": true, "provider": provider_name, "model": test_model, "note": "responded but no content"}));
            }
            let stderr = String::from_utf8_lossy(&output.stderr);
            let stdout = String::from_utf8_lossy(&output.stdout);
            let msg = if !stdout.is_empty() { &*stdout } else { &*stderr };
            let snippet = msg.chars().take(200).collect::<String>();
            Json(serde_json::json!({"success": false, "error": snippet, "provider": provider_name}))
        }
        Err(e) => Json(serde_json::json!({"success": false, "error": e.to_string(), "provider": provider_name})),
    }
}

// ── Hermes Version & Skills Endpoints ──────────────────────────────────────

async fn hermes_version() -> Json<serde_json::Value> {
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

async fn hermes_update() -> Json<serde_json::Value> {
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

async fn hermes_skills() -> Json<serde_json::Value> {
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

// ── Server ─────────────────────────────────────────────────────────────────

#[tokio::main]
async fn main() {
    let state = Arc::new(AppState::new());

    let app = Router::new()
        .route("/health", get(health))
        .route("/config", get(get_config))
        .route("/config/write", post(write_config))
        .route("/config/update", post(update_config))
        .route("/models", get(get_models))
        .route("/models/switch", post(switch_model))
        .route("/models/probe", post(probe_model_handler))
        .route("/chat", post(chat_handler))
        .route("/chat/stream", get(chat_stream_handler))
        .route("/sessions", get(get_sessions))
        .route("/logs", get(get_logs))
        .route("/gateway", get(get_gateway))
        .route("/gateway/toggle", post(gateway_toggle))
        .route("/cron", get(get_cron))
        .route("/providers", get(get_providers))
        .route("/setup/detect", get(detect_setup))
        .route("/setup/install", post(install_hermes))
        .route("/setup/auto-configure", post(auto_configure))
        .route("/setup/probe-provider", post(probe_provider_handler))
        .route("/hermes/version", get(hermes_version))
        .route("/hermes/update", post(hermes_update))
        .route("/hermes/skills", get(hermes_skills))
        .layer(CorsLayer::permissive())
        .with_state(state);

    let addr = "127.0.0.1:9120";
    println!("Hermes Wingman backend running on http://{}", addr);
    println!("Hermes home: {:?}", AppState::new().hermes_home);

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
