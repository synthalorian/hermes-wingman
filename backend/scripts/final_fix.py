import os
import re

os.chdir("/home/synth/projects/hermes_wingman/backend/src")
HANDLERS = "handlers"

def read_file(path):
    with open(path, "r") as f:
        return f.read()

def write_file(path, content):
    with open(path, "w") as f:
        f.write(content)

def strip_bad_imports(content):
    """Remove the bad universal import blocks added by fix_imports.py."""
    # Match use axum::{...}; block through use crate::chat::{...};
    patterns = [
        r'use axum::\{[^}]*\};\s*',
        r'use std::sync::Arc;\s*',
        r'use serde::\{Deserialize, Serialize\};\s*',
        r'use serde_json;\s*',
        r'use crate::state::AppState;\s*',
        r'use crate::platform::\{[^}]*\};\s*',
        r'use crate::helpers::\{[^}]*\};\s*',
        r'use crate::models::\{[^}]*\};\s*',
        r'use crate::chat::\{[^}]*\};\s*',
    ]
    for p in patterns:
        content = re.sub(p, '', content)
    # Clean up excessive blank lines
    content = re.sub(r'\n{3,}', '\n\n', content)
    return content

def add_imports(content, imports):
    if not imports:
        return content
    # Insert after the file comment header if present
    m = re.match(r'(// ──.*?\n\n)', content)
    if m:
        end = m.end()
        return content[:end] + imports + "\n" + content[end:]
    else:
        return imports + "\n" + content

# Map of which symbols each handler file actually needs
NEEDS = {
    "config.rs": {
        "axum": ["extract::State", "http::StatusCode", "response::Json"],
        "std": ["sync::Arc"],
        "serde": ["Serialize", "Deserialize"],
        "crate": ["state::AppState", "platform::{hermes_binary_path, hermes_home_dir, run_hermes}", "helpers::{read_config, read_file, get_active_model}", "models::{discover_models, ModelEntry, ModelsResponse}"],
    },
    "chat_stream.rs": {
        "axum": ["extract::{Query, State}", "response::{Json, Sse}"],
        "std": ["sync::Arc"],
        "serde": ["Deserialize"],
        "crate": ["state::AppState", "platform::{hermes_binary_path, run_hermes}", "helpers::{read_config, load_soul_md, oauth_providers, get_active_model, build_chat_messages, strip_think_tags_stream}"],
    },
    "gateway.rs": {
        "axum": ["extract::{Path, State}", "http::StatusCode", "response::Json"],
        "std": ["sync::Arc", "path::PathBuf", "process::Command"],
        "serde": ["Deserialize"],
        "crate": ["state::AppState", "platform::{hermes_home_dir, hermes_binary_path, run_hermes}", "helpers::{read_config, read_file, oauth_providers, classify_provider, ProviderType}"],
    },
    "setup.rs": {
        "axum": ["extract::State", "http::StatusCode", "response::Json"],
        "std": ["sync::Arc", "net::TcpStream", "time::Duration"],
        "serde": ["Deserialize"],
        "crate": ["state::AppState", "platform::{hermes_home_dir, hermes_binary_path, run_hermes}", "helpers::{read_config, read_file, oauth_providers}"],
    },
    "skills.rs": {
        "axum": ["extract::Path", "http::StatusCode", "response::Json"],
        "serde": ["Deserialize"],
        "crate": ["platform::run_hermes"],
    },
    "memory.rs": {
        "axum": ["extract::{Path, State}", "http::StatusCode", "response::Json", "routing::delete"],
        "std": ["sync::Arc", "path::PathBuf"],
        "serde": ["Deserialize"],
        "crate": ["state::AppState", "platform::{hermes_home_dir, run_hermes}"],
    },
    "files.rs": {
        "axum": ["extract::{Query, State}", "http::StatusCode", "response::Json", "routing::put"],
        "std": ["sync::Arc", "path::PathBuf"],
        "serde": ["Deserialize"],
        "crate": ["state::AppState", "platform::{hermes_home_dir, run_hermes}"],
    },
    "cli.rs": {
        "axum": ["extract::{Path, State, Json}", "http::StatusCode", "response::Json"],
        "std": ["sync::Arc"],
        "serde": ["Deserialize"],
        "crate": ["state::AppState", "platform::{hermes_binary_path, run_hermes}"],
    },
    "auth.rs": {
        "axum": ["extract::{Path, State}", "http::StatusCode", "response::Json"],
        "std": ["sync::Arc", "collections::HashMap"],
        "serde": ["Deserialize"],
        "crate": ["state::AppState", "platform::hermes_home_dir", "helpers::{read_file, oauth_providers}"],
    },
    "metrics.rs": {
        "axum": ["extract::State", "response::Json"],
        "std": ["sync::Arc"],
        "crate": ["state::AppState"],
    },
}

def build_imports(needs):
    lines = []
    if "axum" in needs:
        parts = ", ".join(needs["axum"])
        lines.append(f"use axum::{{{parts}}};")
    if "std" in needs:
        for item in needs["std"]:
            lines.append(f"use std::{item};")
    if "serde" in needs:
        if set(needs["serde"]) == {"Serialize", "Deserialize"}:
            lines.append("use serde::{Deserialize, Serialize};")
        else:
            parts = ", ".join(needs["serde"])
            lines.append(f"use serde::{{{parts}}};")
    if "crate" in needs:
        for item in needs["crate"]:
            lines.append(f"use crate::{item};")
    return "\n".join(lines) + "\n"

# Process each handler file
for fname, needs in NEEDS.items():
    path = f"{HANDLERS}/{fname}"
    content = read_file(path)
    content = strip_bad_imports(content)
    imports = build_imports(needs)
    content = add_imports(content, imports)
    write_file(path, content)
    print(f"Fixed {fname}")

print("Done!")
