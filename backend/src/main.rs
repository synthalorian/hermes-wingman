use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::{Json, Sse},
    routing::{delete, get, post, put},
    Router,
};
use futures::stream::Stream;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::process::Command;
use std::sync::Arc;
use std::sync::Mutex;
use tokio::sync::oneshot;
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

/// Resolve the absolute path to the `hermes` binary using `find_hermes_binary()`.
/// Falls back to "hermes" (PATH lookup) if not found.
fn hermes_binary_path() -> String {
    find_hermes_binary().unwrap_or_else(|| "hermes".to_string())
}

/// Run `hermes` CLI command (platform-agnostic)
fn run_hermes(args: &[&str]) -> Result<(String, String, i32), String> {
    let binary = hermes_binary_path();
    let output = Command::new(&binary)
        .args(args)
        .env("PAGER", "cat")
        .output()
        .map_err(|e| format!("Failed to run hermes ({}): {}", binary, e))?;

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
    /// Tracks running OAuth login processes.
    /// Map of provider name -> oneshot sender for the auth URL.
    auth_urls: Arc<Mutex<HashMap<String, oneshot::Sender<String>>>>,
}

impl AppState {
    fn new() -> Self {
        Self {
            hermes_home: hermes_home_dir(),
            override_model: Arc::new(Mutex::new(None)),
            auth_urls: Arc::new(Mutex::new(HashMap::new())),
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

// ── Gateway Platforms ───────────────────────────────────────────────────────

/// Helper: read a value from ~/.hermes/.env
fn get_env_value(key: &str, home: &PathBuf) -> String {
    let env_path = home.join(".env");
    match read_file(&env_path) {
        Ok(content) => {
            for line in content.lines() {
                let trimmed = line.trim();
                if let Some(val) = trimmed.strip_prefix(&format!("{}=", key)) {
                    return val.to_string();
                }
                if let Some(val) = trimmed.strip_prefix(&format!("# {}=", key)) {
                    return val.to_string();
                }
            }
            String::new()
        }
        Err(_) => String::new(),
    }
}

/// Helper: save a value to ~/.hermes/.env via Python helper
fn save_env_value(key: &str, value: &str) -> Result<String, String> {
    let py_script = std::path::Path::new("/tmp/save_env.py");
    if !py_script.exists() {
        let s = r##"import os, sys
def save_env_value(key, value):
    env_path = os.path.expanduser("~/.hermes/.env")
    content = ""
    if os.path.exists(env_path):
        with open(env_path) as f:
            content = f.read()
    lines = content.splitlines(keepends=True)
    found = False
    new_lines = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith(key + "=") or stripped.startswith("# " + key + "="):
            if not found:
                new_lines.append(f"{key}={value}\n")
                found = True
        else:
            new_lines.append(line)
    if not found:
        new_lines.append(f"{key}={value}\n")
    with open(env_path, "w") as f:
        f.writelines(new_lines)
    print(f"Saved {key}")
if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "set":
        save_env_value(sys.argv[2], sys.argv[3])
    elif len(sys.argv) >= 3 and sys.argv[1] == "get":
        import os
        env_path = os.path.expanduser("~/.hermes/.env")
        if os.path.exists(env_path):
            with open(env_path) as f:
                for line in f:
                    s = line.strip()
                    if s.startswith(sys.argv[2] + "="):
                        print(s[len(sys.argv[2])+1:])
                        break
"##;
        std::fs::write(py_script, s).map_err(|e| format!("Create helper: {}", e))?;
    }
    let output = Command::new("python3")
        .args([py_script.to_str().unwrap_or("/tmp/save_env.py"), "set", key, value])
        .output()
        .map_err(|e| format!("Run helper: {}", e))?;
    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).trim().to_string())
    }
}

/// All known gateway platforms with their metadata and field schemas.
fn get_platform_definitions() -> Vec<serde_json::Value> {
    vec![
        serde_json::json!({"key":"telegram","label":"Telegram","emoji":"📱","token_var":"TELEGRAM_BOT_TOKEN",
            "instructions":["1. Open Telegram and message @BotFather","2. Send /newbot to create your bot","3. Copy the bot token","4. Get your user ID: message @userinfobot"],
            "vars":[
                {"name":"TELEGRAM_BOT_TOKEN","prompt":"Bot token","password":true,"help":"Paste the token from @BotFather."},
                {"name":"TELEGRAM_ALLOWED_USERS","prompt":"Allowed user IDs (comma-separated)","password":false,"is_allowlist":true,"help":"Your numeric user ID."},
            ]}),
        serde_json::json!({"key":"discord","label":"Discord","emoji":"🎮","token_var":"DISCORD_BOT_TOKEN",
            "instructions":["1. https://discord.com/developers/applications → New Application","2. Bot → Reset Token → copy","3. OAuth2 URL Generator → bot scope","4. Invite bot to your server","5. Enable Developer Mode → right-click name → Copy ID"],
            "vars":[
                {"name":"DISCORD_BOT_TOKEN","prompt":"Bot token","password":true,"help":"From Discord Developer Portal."},
                {"name":"DISCORD_ALLOWED_USERS","prompt":"Allowed user IDs","password":false,"is_allowlist":true,"help":"Your Discord user ID."},
            ]}),
        serde_json::json!({"key":"slack","label":"Slack","emoji":"💼","token_var":"SLACK_BOT_TOKEN",
            "instructions":["1. https://api.slack.com/apps → Create New App","2. Enable Socket Mode","3. Add Bot Token Scopes","4. Install to Workspace"],
            "vars":[
                {"name":"SLACK_BOT_TOKEN","prompt":"Bot Token (xoxb-...)","password":true},
                {"name":"SLACK_APP_TOKEN","prompt":"App Token (xapp-...)","password":true},
            ]}),
        serde_json::json!({"key":"signal","label":"Signal","emoji":"📡","token_var":"SIGNAL_HTTP_URL",
            "instructions":["Run a Signal REST API server and enter the URL below."],
            "vars":[{"name":"SIGNAL_HTTP_URL","prompt":"Signal REST API URL","password":false,"help":"e.g. http://localhost:8080"}]}),
        serde_json::json!({"key":"email","label":"Email","emoji":"📧","token_var":"EMAIL_ADDRESS",
            "instructions":["Use a dedicated email account. For Gmail: enable 2FA + create App Password."],
            "vars":[
                {"name":"EMAIL_ADDRESS","prompt":"Email address","password":false},
                {"name":"EMAIL_PASSWORD","prompt":"Email password (or app password)","password":true},
                {"name":"EMAIL_IMAP_HOST","prompt":"IMAP host","password":false,"help":"e.g. imap.gmail.com"},
                {"name":"EMAIL_SMTP_HOST","prompt":"SMTP host","password":false,"help":"e.g. smtp.gmail.com"},
                {"name":"EMAIL_ALLOWED_USERS","prompt":"Allowed sender emails","password":false,"is_allowlist":true},
            ]}),
        serde_json::json!({"key":"sms","label":"SMS (Twilio)","emoji":"📱","token_var":"TWILIO_ACCOUNT_SID",
            "instructions":["Create a Twilio account and buy a phone number."],
            "vars":[
                {"name":"TWILIO_ACCOUNT_SID","prompt":"Account SID","password":false},
                {"name":"TWILIO_AUTH_TOKEN","prompt":"Auth Token","password":true},
                {"name":"TWILIO_PHONE_NUMBER","prompt":"Phone number (E.164)","password":false,"help":"e.g. +15551234567"},
            ]}),
        serde_json::json!({"key":"matrix","label":"Matrix","emoji":"🔐","token_var":"MATRIX_ACCESS_TOKEN",
            "instructions":["Works with any Matrix homeserver. Create a bot user."],
            "vars":[
                {"name":"MATRIX_HOMESERVER","prompt":"Homeserver URL","password":false,"help":"e.g. https://matrix.example.org"},
                {"name":"MATRIX_ACCESS_TOKEN","prompt":"Access token","password":true,"help":"Or leave empty for password login."},
                {"name":"MATRIX_ALLOWED_USERS","prompt":"Allowed user IDs","password":false,"is_allowlist":true},
            ]}),
        serde_json::json!({"key":"mattermost","label":"Mattermost","emoji":"💬","token_var":"MATTERMOST_TOKEN",
            "instructions":["Integrations → Bot Accounts → Add Bot Account"],
            "vars":[
                {"name":"MATTERMOST_URL","prompt":"Server URL","password":false,"help":"e.g. https://mm.example.com"},
                {"name":"MATTERMOST_TOKEN","prompt":"Bot token","password":true},
                {"name":"MATTERMOST_ALLOWED_USERS","prompt":"Allowed user IDs","password":false,"is_allowlist":true},
            ]}),
        serde_json::json!({"key":"whatsapp","label":"WhatsApp","emoji":"📲","token_var":"WHATSAPP_ENABLED",
            "instructions":["Enable and use QR code pairing via the gateway."],"vars":[]}),
        serde_json::json!({"key":"dingtalk","label":"DingTalk","emoji":"💬","token_var":"DINGTALK_CLIENT_ID",
            "instructions":["https://open-dev.dingtalk.com → Create Application"],
            "vars":[
                {"name":"DINGTALK_CLIENT_ID","prompt":"AppKey (Client ID)","password":false},
                {"name":"DINGTALK_CLIENT_SECRET","prompt":"AppSecret","password":true},
            ]}),
        serde_json::json!({"key":"feishu","label":"Feishu / Lark","emoji":"🪽","token_var":"FEISHU_APP_ID",
            "instructions":["https://open.feishu.cn/ → Create app and enable Bot capability"],
            "vars":[
                {"name":"FEISHU_APP_ID","prompt":"App ID","password":false},
                {"name":"FEISHU_APP_SECRET","prompt":"App Secret","password":true},
            ]}),
        serde_json::json!({"key":"wecom","label":"WeCom","emoji":"💬","token_var":"WECOM_BOT_ID",
            "instructions":["WeCom Admin Console → Applications → Create AI Bot"],
            "vars":[
                {"name":"WECOM_BOT_ID","prompt":"Bot ID","password":false},
                {"name":"WECOM_SECRET","prompt":"Secret","password":true},
            ]}),
        serde_json::json!({"key":"weixin","label":"Weixin / WeChat","emoji":"💬","token_var":"WEIXIN_ACCOUNT_ID",
            "instructions":["Configure via Weixin Official Account platform."],"vars":[]}),
        serde_json::json!({"key":"bluebubbles","label":"BlueBubbles","emoji":"💬","token_var":"BLUEBUBBLES_SERVER_URL",
            "instructions":["Install BlueBubbles on a Mac: https://bluebubbles.app/"],
            "vars":[
                {"name":"BLUEBUBBLES_SERVER_URL","prompt":"Server URL","password":false,"help":"e.g. http://192.168.1.10:1234"},
                {"name":"BLUEBUBBLES_PASSWORD","prompt":"Password","password":true},
            ]}),
        serde_json::json!({"key":"qqbot","label":"QQ Bot","emoji":"🐧","token_var":"QQ_APP_ID",
            "instructions":["Register at q.qq.com"],
            "vars":[
                {"name":"QQ_APP_ID","prompt":"App ID","password":false},
                {"name":"QQ_CLIENT_SECRET","prompt":"App Secret","password":true},
            ]}),
        serde_json::json!({"key":"yuanbao","label":"Yuanbao","emoji":"💎","token_var":"YUANBAO_APP_ID",
            "instructions":["Download from https://yuanbao.tencent.com/ → Create a bot"],
            "vars":[
                {"name":"YUANBAO_APP_ID","prompt":"App ID","password":false},
                {"name":"YUANBAO_APP_SECRET","prompt":"App Secret","password":true},
            ]}),
    ]
}

/// Get all gateway platforms with their metadata and current config status.
async fn gateway_get_platforms(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    let home = state.hermes_home.clone();
    let definitions = get_platform_definitions();

    let gw_path = state.gateway_state_path();
    let gateway_state = read_file(&gw_path).ok()
        .and_then(|c| serde_json::from_str::<serde_json::Value>(&c).ok());

    let mut result = Vec::new();
    for mut platform in definitions {
        let key = platform["key"].as_str().unwrap_or("").to_string();
        let token_var = platform["token_var"].as_str().unwrap_or("");

        let has_token = if !token_var.is_empty() {
            let val = get_env_value(token_var, &home);
            !val.is_empty() && !val.starts_with('<') && !val.starts_with('#')
        } else {
            false
        };

        let runtime_status = gateway_state.as_ref()
            .and_then(|g| g["platforms"].get(&key))
            .and_then(|p| p["state"].as_str())
            .unwrap_or("disconnected");

        let status = if has_token {
            if runtime_status == "connected" { "connected" }
            else if runtime_status == "retrying" || runtime_status == "error" { "error" }
            else { "configured" }
        } else {
            "not_configured"
        };

        if let Some(vars) = platform["vars"].as_array_mut() {
            for var in vars.iter_mut() {
                let name = var["name"].as_str().unwrap_or("");
                let is_password = var.get("password").and_then(|p| p.as_bool()).unwrap_or(false);
                let current = get_env_value(name, &home);
                if !current.is_empty() {
                    var["current"] = serde_json::json!(
                        if is_password {
                            if current.len() > 8 { format!("{}…{}", &current[..4], &current[current.len()-4..]) }
                            else { "••••••••".to_string() }
                        } else { current }
                    );
                }
            }
        }

        platform["status"] = serde_json::json!(status);
        platform["runtime_status"] = serde_json::json!(runtime_status);
        platform["has_token"] = serde_json::json!(has_token);
        result.push(platform);
    }

    Json(serde_json::json!(result))
}

/// Configure a gateway platform by saving its env vars.
async fn gateway_configure_platform(
    Path(platform): Path<String>,
    Json(body): Json<serde_json::Value>,
) -> Json<serde_json::Value> {
    let vars = body["vars"].as_object().cloned();
    let vars = match vars {
        Some(v) => v,
        None => return Json(serde_json::json!({"success": false, "error": "vars object required"})),
    };

    let mut errors = Vec::new();
    let mut saved = Vec::new();

    for (key, value) in &vars {
        let val = value.as_str().unwrap_or("");
        match save_env_value(key, val) {
            Ok(msg) => saved.push(msg),
            Err(e) => errors.push(format!("{}: {}", key, e)),
        }
    }

    Json(serde_json::json!({
        "success": errors.is_empty(),
        "platform": platform,
        "saved": saved,
        "errors": if errors.is_empty() { serde_json::Value::Null } else { serde_json::json!(errors) },
    }))
}

/// Gateway service management.
async fn gateway_service_action(
    Path(action): Path<String>,
) -> Json<serde_json::Value> {
    let hermes_args: &[&str] = match action.as_str() {
        "install" => &["gateway", "install"],
        "uninstall" => &["gateway", "uninstall"],
        "start" => &["gateway", "start"],
        "stop" => &["gateway", "stop"],
        "restart" => &["gateway", "restart"],
        "status" => &["gateway", "status"],
        _ => return Json(serde_json::json!({"success": false, "error": format!("Unknown action: {}", action)})),
    };

    if action == "stop" {
        match std::process::Command::new(hermes_binary_path())
            .args(hermes_args)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
        {
            Ok(mut child) => {
                if let Some(stdin) = child.stdin.take() {
                    use std::io::Write;
                    let _ = write!(&stdin, "y\n");
                    drop(stdin);
                }
                match child.wait_with_output() {
                    Ok(output) => Json(serde_json::json!({
                        "success": output.status.success(),
                        "action": action,
                        "stdout": String::from_utf8_lossy(&output.stdout).trim(),
                        "stderr": String::from_utf8_lossy(&output.stderr).trim(),
                    })),
                    Err(e) => Json(serde_json::json!({"success": false, "error": e.to_string()})),
                }
            }
            Err(e) => Json(serde_json::json!({"success": false, "error": e.to_string()})),
        }
    } else {
        match run_hermes(hermes_args) {
            Ok((stdout, stderr, code)) => Json(serde_json::json!({
                "success": code == 0,
                "action": action,
                "stdout": stdout.trim(),
                "stderr": stderr.trim(),
            })),
            Err(e) => Json(serde_json::json!({"success": false, "error": e})),
        }
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
            match std::process::Command::new(hermes_binary_path())
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
    let method = body.method.as_deref().unwrap_or("curl");

    match method {
        "curl" | "auto" => {
            // Primary method: official Hermes install script
            // curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
            match Command::new("bash")
                .arg("-c")
                .arg("curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash")
                .output()
            {
                Ok(output) if output.status.success() => {
                    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
                    Json(serde_json::json!({"success": true, "method": "curl", "output": stdout.chars().take(1000).collect::<String>()}))
                }
                Ok(output) => {
                    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
                    let out_stdout = String::from_utf8_lossy(&output.stdout).to_string();
                    let has_curl = Command::new("which").arg("curl").output().map(|o| o.status.success()).unwrap_or(false);
                    let has_wget = Command::new("which").arg("wget").output().map(|o| o.status.success()).unwrap_or(false);
                    
                    if !has_curl && !has_wget {
                        return Json(serde_json::json!({
                            "success": false,
                            "error": "curl is not installed on this system. Please install curl first:\n  apt install curl   # Debian/Ubuntu\n  pacman -S curl      # Arch\n  brew install curl   # macOS\n  yum install curl    # RHEL/Fedora\n\nThen run the setup again.",
                            "needs_curl": true,
                        }));
                    }
                    
                    Json(serde_json::json!({
                        "success": false,
                        "method": "curl",
                        "error": stderr.chars().take(500).collect::<String>(),
                        "stdout": out_stdout.chars().take(200).collect::<String>(),
                    }))
                }
                Err(e) => Json(serde_json::json!({
                    "success": false,
                    "error": format!("Failed to run installer: {}", e),
                })),
            }
        }
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

// ── Skills Toggle ──────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct SkillToggleParams {
    action: Option<String>,
}

async fn hermes_skills_toggle(
    axum::extract::Path(name): axum::extract::Path<String>,
    Json(body): Json<serde_json::Value>,
) -> Json<serde_json::Value> {
    let action = body["action"].as_str().unwrap_or("toggle");
    let args: Vec<&str> = match action {
        "enable" => vec!["skills", "enable", &name],
        "disable" => vec!["skills", "disable", &name],
        _ => vec!["skills", "toggle", &name],
    };
    match run_hermes(&args) {
        Ok((stdout, stderr, code)) => {
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

// ── Memory ──────────────────────────────────────────────────────────────────

async fn memory_list() -> Json<serde_json::Value> {
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

async fn memory_get(
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

async fn memory_delete(
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

async fn memory_search(
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

// ── File Operations ─────────────────────────────────────────────────────────

/// Resolve a filesystem path, allowing navigation outside ~/.hermes.
/// If the path starts with '/', use it as-is (absolute path).
/// Otherwise, resolve relative to the user's HOME.
fn resolve_fs_path(state: &AppState, relative_path: &str) -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    if relative_path.starts_with('/') {
        // Absolute path — use as-is (filesystem-wide access)
        PathBuf::from(relative_path)
    } else if relative_path.is_empty() || relative_path == "." {
        PathBuf::from(&home)
    } else if relative_path.starts_with("~/") {
        PathBuf::from(&home).join(&relative_path[2..])
    } else if relative_path.starts_with("./") {
        PathBuf::from(&home).join(&relative_path[2..])
    } else {
        // Relative path — resolve from home
        PathBuf::from(&home).join(relative_path)
    }
}

#[derive(Deserialize)]
struct FileListQuery {
    path: Option<String>,
}

async fn files_list(
    State(state): State<Arc<AppState>>,
    Query(query): Query<FileListQuery>,
) -> Json<serde_json::Value> {
    let dir_path = resolve_fs_path(&state, query.path.as_deref().unwrap_or(""));
    match std::fs::read_dir(&dir_path) {
        Ok(entries) => {
            let mut files = Vec::new();
            let mut dirs = Vec::new();
            for entry in entries {
                if let Ok(entry) = entry {
                    let name = entry.file_name().to_string_lossy().to_string();
                    if name.starts_with('.') { continue; }
                    if entry.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                        dirs.push(name);
                    } else {
                        files.push(name);
                    }
                }
            }
            dirs.sort();
            files.sort();
            Json(serde_json::json!({
                "success": true,
                "path": dir_path.to_string_lossy().to_string(),
                "directories": dirs,
                "files": files,
                "parent": query.path.as_deref().unwrap_or("").rsplit_once('/').map(|(p, _)| p.to_string()).unwrap_or_default(),
            }))
        }
        Err(e) => Json(serde_json::json!({
            "success": false,
            "error": format!("Cannot read directory: {}", e),
        })),
    }
}

#[derive(Deserialize)]
struct FileReadQuery {
    path: String,
}

async fn files_read(
    State(state): State<Arc<AppState>>,
    Query(query): Query<FileReadQuery>,
) -> Json<serde_json::Value> {
    let full_path = resolve_fs_path(&state, &query.path);
    if !full_path.exists() {
        return Json(serde_json::json!({
            "success": false,
            "error": "File not found",
        }));
    }
    if full_path.is_dir() {
        return Json(serde_json::json!({
            "success": false,
            "error": "Path is a directory",
        }));
    }
    match std::fs::read_to_string(&full_path) {
        Ok(content) => Json(serde_json::json!({
            "success": true,
            "path": query.path,
            "content": content,
            "size": content.len(),
        })),
        Err(e) => Json(serde_json::json!({
            "success": false,
            "error": format!("Cannot read file: {}", e),
        })),
    }
}

#[derive(Deserialize)]
struct FileWriteBody {
    path: String,
    content: String,
}

async fn files_write(
    State(state): State<Arc<AppState>>,
    Json(body): Json<FileWriteBody>,
) -> Json<serde_json::Value> {
    let full_path = resolve_fs_path(&state, &body.path);
    if let Some(parent) = full_path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    match std::fs::write(&full_path, &body.content) {
        Ok(()) => Json(serde_json::json!({
            "success": true,
            "path": body.path,
            "size": body.content.len(),
        })),
        Err(e) => Json(serde_json::json!({
            "success": false,
            "error": format!("Cannot write file: {}", e),
        })),
    }
}

// ── File Operations (Info, Delete, Rename, Mkdir) ────────────────────────

#[derive(Deserialize)]
struct FileQuery {
    path: String,
}

async fn files_info(
    State(state): State<Arc<AppState>>,
    Query(query): Query<FileQuery>,
) -> Json<serde_json::Value> {
    let full_path = resolve_fs_path(&state, &query.path);
    if !full_path.exists() {
        return Json(serde_json::json!({"success": false, "error": "Path not found"}));
    }
    let metadata = match std::fs::metadata(&full_path) {
        Ok(m) => m,
        Err(e) => return Json(serde_json::json!({"success": false, "error": e.to_string()})),
    };
    use std::os::unix::fs::PermissionsExt;
    let perms = metadata.permissions().mode();
    let is_dir = metadata.is_dir();
    let size = metadata.len();
    let modified = metadata.modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0);

    Json(serde_json::json!({
        "success": true,
        "name": full_path.file_name().map(|n| n.to_string_lossy()).unwrap_or_default(),
        "path": query.path,
        "is_dir": is_dir,
        "size": size,
        "modified": modified,
        "permissions": format!("{:o}", perms & 0o777),
    }))
}

async fn files_delete(
    State(state): State<Arc<AppState>>,
    Json(body): Json<FileQuery>,
) -> Json<serde_json::Value> {
    let full_path = resolve_fs_path(&state, &body.path);
    if !full_path.exists() {
        return Json(serde_json::json!({"success": false, "error": "Path not found"}));
    }
    let result = if full_path.is_dir() {
        std::fs::remove_dir_all(&full_path)
    } else {
        std::fs::remove_file(&full_path)
    };
    match result {
        Ok(()) => Json(serde_json::json!({"success": true, "path": body.path})),
        Err(e) => Json(serde_json::json!({"success": false, "error": e.to_string()})),
    }
}

#[derive(Deserialize)]
struct FileRenameBody {
    path: String,
    new_name: String,
}

async fn files_rename(
    State(state): State<Arc<AppState>>,
    Json(body): Json<FileRenameBody>,
) -> Json<serde_json::Value> {
    let full_path = resolve_fs_path(&state, &body.path);
    if !full_path.exists() {
        return Json(serde_json::json!({"success": false, "error": "Path not found"}));
    }
    let parent = full_path.parent().unwrap_or(std::path::Path::new("/"));
    let new_path = parent.join(&body.new_name);
    match std::fs::rename(&full_path, &new_path) {
        Ok(()) => Json(serde_json::json!({"success": true, "from": body.path, "to": body.new_name})),
        Err(e) => Json(serde_json::json!({"success": false, "error": e.to_string()})),
    }
}

#[derive(Deserialize)]
struct FileMkdirBody {
    path: String,
    name: String,
}

async fn files_mkdir(
    State(state): State<Arc<AppState>>,
    Json(body): Json<FileMkdirBody>,
) -> Json<serde_json::Value> {
    let base_path = resolve_fs_path(&state, &body.path);
    let dir_path = base_path.join(&body.name);
    match std::fs::create_dir(&dir_path) {
        Ok(()) => Json(serde_json::json!({"success": true, "path": format!("{}/{}", body.path, body.name)})),
        Err(e) => Json(serde_json::json!({"success": false, "error": e.to_string()})),
    }
}

// ── Generic Hermes Command Runner ────────────────────────────────────────────

#[derive(Deserialize)]
struct HermesCommandBody {
    args: Vec<String>,
}

async fn hermes_command(
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

async fn cli_fallback_list() -> Json<serde_json::Value> {
    match run_hermes(&["fallback", "list"]) {
        Ok((stdout, _, _)) => {
            let lines: Vec<String> = stdout.lines().map(|l| l.trim().to_string()).filter(|l| !l.is_empty()).collect();
            Json(serde_json::json!({ "success": true, "chain": lines }))
        },
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

async fn cli_fallback_add(Json(body): Json<serde_json::Value>) -> Json<serde_json::Value> {
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

async fn cli_fallback_clear() -> Json<serde_json::Value> {
    match run_hermes(&["fallback", "clear"]) {
        Ok((stdout, _, code)) => Json(serde_json::json!({ "success": code == 0, "stdout": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

async fn cli_webhook_list() -> Json<serde_json::Value> {
    match run_hermes(&["webhook", "list"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "webhooks": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

async fn cli_hooks_list() -> Json<serde_json::Value> {
    match run_hermes(&["hooks", "list"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "hooks": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

async fn cli_plugins_list() -> Json<serde_json::Value> {
    match run_hermes(&["plugins", "list"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "plugins": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

async fn cli_curator_status() -> Json<serde_json::Value> {
    match run_hermes(&["curator", "status"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "status": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

async fn cli_mcp_list() -> Json<serde_json::Value> {
    match run_hermes(&["mcp", "list"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "servers": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

async fn cli_doctor() -> Json<serde_json::Value> {
    match run_hermes(&["doctor"]) {
        Ok((stdout, _, code)) => Json(serde_json::json!({ "success": code == 0, "output": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

async fn cli_security_audit() -> Json<serde_json::Value> {
    match run_hermes(&["security", "audit"]) {
        Ok((stdout, _, code)) => Json(serde_json::json!({ "success": code == 0, "output": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

async fn cli_dump() -> Json<serde_json::Value> {
    match run_hermes(&["dump"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "dump": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

async fn cli_debug_share() -> Json<serde_json::Value> {
    match run_hermes(&["debug", "share", "--local"]) {
        Ok((stdout, _, code)) => Json(serde_json::json!({ "success": code == 0, "output": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

async fn cli_backup_create() -> Json<serde_json::Value> {
    match run_hermes(&["backup", "--quick"]) {
        Ok((stdout, _, code)) => Json(serde_json::json!({ "success": code == 0, "output": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

async fn cli_checkpoints_status() -> Json<serde_json::Value> {
    match run_hermes(&["checkpoints", "status"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "status": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

async fn cli_proxy_status() -> Json<serde_json::Value> {
    match run_hermes(&["proxy", "status"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "status": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

async fn cli_secrets_status() -> Json<serde_json::Value> {
    match run_hermes(&["secrets", "bitwarden", "status"]) {
        Ok((stdout, _, code)) => Json(serde_json::json!({ "success": code == 0, "output": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

async fn cli_pairing_list() -> Json<serde_json::Value> {
    match run_hermes(&["pairing", "list"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "users": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

async fn cli_insights() -> Json<serde_json::Value> {
    match run_hermes(&["insights", "--days", "7"]) {
        Ok((stdout, _, _)) => Json(serde_json::json!({ "success": true, "insights": stdout.trim() })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e })),
    }
}

// ── Auth / Provider Login ───────────────────────────────────────────────────

/// Start an OAuth login flow for a provider.
/// Spawns `hermes auth add --type oauth --no-browser {provider}` in background,
/// captures the auth URL from stdout, and returns it to Flutter.
/// The hermes process continues running to handle the OAuth callback.
async fn auth_start_oauth(
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
async fn auth_add_api_key(
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
async fn auth_get_status(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
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
async fn auth_logout(
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
        .route("/gateway/platforms", get(gateway_get_platforms))
        .route("/gateway/configure/{platform}", post(gateway_configure_platform))
        .route("/gateway/service/{action}", post(gateway_service_action))
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
        .route("/hermes/skills/{name}/toggle", post(hermes_skills_toggle))
        .route("/hermes/command", post(hermes_command))
        .route("/memory", get(memory_list))
        .route("/memory/search", post(memory_search))
        .route("/memory/{id}", get(memory_get))
        .route("/memory/{id}", delete(memory_delete))
        .route("/files/list", get(files_list))
        .route("/files/read", get(files_read))
        .route("/files/write", put(files_write))
        .route("/files/info", get(files_info))
        .route("/files/delete", post(files_delete))
        .route("/files/rename", post(files_rename))
        .route("/files/mkdir", post(files_mkdir))
        // Auth / Provider Login
        .route("/auth/status", get(auth_get_status))
        .route("/auth/login/{provider}", post(auth_start_oauth))
        .route("/auth/api-key", post(auth_add_api_key))
        .route("/auth/logout/{provider}", post(auth_logout))
        // CLI Proxy endpoints (fallback, webhooks, hooks, plugins, curator, MCP, etc.)
        .route("/cli/fallback", get(cli_fallback_list))
        .route("/cli/fallback/add", post(cli_fallback_add))
        .route("/cli/fallback/clear", post(cli_fallback_clear))
        .route("/cli/webhooks", get(cli_webhook_list))
        .route("/cli/hooks", get(cli_hooks_list))
        .route("/cli/plugins", get(cli_plugins_list))
        .route("/cli/curator", get(cli_curator_status))
        .route("/cli/mcp", get(cli_mcp_list))
        .route("/cli/doctor", get(cli_doctor))
        .route("/cli/security", get(cli_security_audit))
        .route("/cli/dump", get(cli_dump))
        .route("/cli/debug", get(cli_debug_share))
        .route("/cli/backup", post(cli_backup_create))
        .route("/cli/checkpoints", get(cli_checkpoints_status))
        .route("/cli/proxy", get(cli_proxy_status))
        .route("/cli/secrets", get(cli_secrets_status))
        .route("/cli/pairing", get(cli_pairing_list))
        .route("/cli/insights", get(cli_insights))
        .layer(CorsLayer::permissive())
        .with_state(state);

    let addr = std::env::var("BIND_ADDR").unwrap_or_else(|_| "127.0.0.1:9120".to_string());
    println!("Hermes Wingman backend running on http://{}", addr);
    println!("Hermes home: {:?}", AppState::new().hermes_home);

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
