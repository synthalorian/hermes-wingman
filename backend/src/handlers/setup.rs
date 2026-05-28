use axum::{extract::State, response::Json};
use std::sync::Arc;
use crate::state::AppState;
use crate::platform::run_hermes;
use crate::helpers::{read_config, read_file, oauth_providers};

// Re-export detect_setup and install_hermes from gateway.rs so main.rs routes work
pub use crate::handlers::gateway::{detect_setup, install_hermes};

// ─── Auto-Configure ─────────────────────────────────────────────────────────

/// Scan the environment for available providers and generate a config.
pub async fn auto_configure(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
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
pub fn check_port(port: u16) -> bool {
    use std::net::TcpStream;
    TcpStream::connect_timeout(
        &format!("127.0.0.1:{}", port).parse().unwrap(),
        std::time::Duration::from_millis(500),
    ).is_ok()
}

/// Strip <think>...</think> reasoning tags from model output.
pub fn strip_think_tags_stream(s: &str, in_think: &mut bool) -> String {
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
pub async fn probe_provider_handler(
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

