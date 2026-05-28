use axum::{extract::{Path, State}, http::StatusCode, response::Json};
use std::sync::Arc;
use std::path::PathBuf;
use std::process::Command;
use serde::{Deserialize};
use crate::state::AppState;
use crate::platform::{hermes_home_dir, hermes_binary_path, find_hermes_binary, run_hermes};
use crate::helpers::{read_config, read_file, oauth_providers, classify_provider, ProviderType};

// ── Gateway Platforms ───────────────────────────────────────────────────────

/// Helper: read a value from ~/.hermes/.env
pub fn get_env_value(key: &str, home: &PathBuf) -> String {
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
pub fn save_env_value(key: &str, value: &str) -> Result<String, String> {
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
pub fn get_platform_definitions() -> Vec<serde_json::Value> {
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
pub async fn gateway_get_platforms(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
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
pub async fn gateway_configure_platform(
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
pub async fn gateway_service_action(
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

pub async fn get_gateway(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
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

pub async fn gateway_toggle(
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

pub async fn get_cron() -> Json<serde_json::Value> {
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

pub async fn get_providers(State(_state): State<Arc<AppState>>) -> Json<serde_json::Value> {
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

pub async fn detect_setup(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
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

pub async fn install_hermes(Json(body): Json<InstallRequest>) -> Json<serde_json::Value> {
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

pub fn detect_os_install_instructions() -> String {
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

