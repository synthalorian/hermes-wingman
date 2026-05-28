use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::{Mutex, oneshot};
use crate::platform::hermes_home_dir;

// ── State ─────────────────────────────────────────────────────────────────

#[derive(Clone)]
pub struct AppState {
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
    pub fn new() -> Self {
        Self {
            hermes_home: hermes_home_dir(),
            override_model: Arc::new(Mutex::new(None)),
            auth_urls: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub fn config_path(&self) -> PathBuf {
        self.hermes_home.join("config.yaml")
    }

    pub fn gateway_state_path(&self) -> PathBuf {
        self.hermes_home.join("gateway_state.json")
    }

    pub fn logs_dir(&self) -> PathBuf {
        self.hermes_home.join("logs")
    }

    pub fn agent_log(&self) -> PathBuf {
        self.logs_dir().join("agent.log")
    }
}

