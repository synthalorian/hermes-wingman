use std::path::PathBuf;
use std::process::Command;

// ── Platform Helpers ─────────────────────────────────────────────────────────

/// Cross-platform hermes home directory.
/// Linux/macOS: ~/.hermes
/// Windows: %LOCALAPPDATA%\hermes
pub fn hermes_home_dir() -> PathBuf {
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
pub fn find_hermes_binary() -> Option<String> {
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
pub fn hermes_binary_path() -> String {
    find_hermes_binary().unwrap_or_else(|| "hermes".to_string())
}

/// Run `hermes` CLI command (platform-agnostic)
pub fn run_hermes(args: &[&str]) -> Result<(String, String, i32), String> {
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

