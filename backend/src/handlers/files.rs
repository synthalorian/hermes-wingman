use axum::{extract::{Query, State}, response::Json};
use std::sync::Arc;
use std::path::PathBuf;
use serde::{Deserialize};
use crate::state::AppState;

// ── File Operations ─────────────────────────────────────────────────────────

/// Resolve a filesystem path, allowing navigation outside ~/.hermes.
/// If the path starts with '/', use it as-is (absolute path).
/// Otherwise, resolve relative to the user's HOME.
pub fn resolve_fs_path(_state: &AppState, relative_path: &str) -> PathBuf {
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
pub struct FileListQuery {
    path: Option<String>,
}

pub async fn files_list(
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
pub struct FileReadQuery {
    path: String,
}

pub async fn files_read(
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
pub struct FileWriteBody {
    path: String,
    content: String,
}

pub async fn files_write(
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
pub struct FileQuery {
    path: String,
}

pub async fn files_info(
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

pub async fn files_delete(
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
pub struct FileRenameBody {
    path: String,
    new_name: String,
}

pub async fn files_rename(
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
pub struct FileMkdirBody {
    path: String,
    name: String,
}

pub async fn files_mkdir(
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

