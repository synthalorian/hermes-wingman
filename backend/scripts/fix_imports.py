import os
import re

SRC = "src"
HANDLERS = "src/handlers"

def read_file(path):
    with open(path, "r") as f:
        return f.read()

def write_file(path, content):
    with open(path, "w") as f:
        f.write(content)

def fix_state():
    path = f"{SRC}/state.rs"
    content = read_file(path)
    imports = """use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::{Mutex, oneshot};
use crate::platform::hermes_home_dir;

"""
    if "use std::" not in content:
        content = imports + content
    write_file(path, content)
    print("Fixed state.rs")

def fix_platform():
    path = f"{SRC}/platform.rs"
    content = read_file(path)
    imports = """use std::path::PathBuf;
use std::process::Command;

"""
    if "use std::" not in content:
        content = imports + content
    write_file(path, content)
    print("Fixed platform.rs")

def fix_helpers():
    path = f"{SRC}/helpers.rs"
    content = read_file(path)
    imports = """use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::time::Duration;
use std::net::TcpStream;
use crate::platform::{hermes_home_dir, run_hermes};
use crate::state::AppState;
use serde::{Serialize, Deserialize};

"""
    if "use std::" not in content:
        content = imports + content
    write_file(path, content)
    print("Fixed helpers.rs")

def fix_models():
    path = f"{SRC}/models.rs"
    content = read_file(path)
    imports = """use std::collections::HashSet;
use serde::Serialize;
use crate::helpers::{read_config, read_file, oauth_providers, universal_cloud_catalog, classify_provider, ProviderType};
use crate::platform::{hermes_home_dir, run_hermes};

"""
    if "use serde::" not in content:
        content = imports + content
    write_file(path, content)
    print("Fixed models.rs")

def fix_chat():
    path = f"{SRC}/chat.rs"
    content = read_file(path)
    imports = """use serde::{Deserialize, Serialize};
use crate::helpers::{read_config, load_soul_md, oauth_providers, run_hermes, get_active_model};
use crate::platform::hermes_binary_path;

"""
    if "use serde::" not in content:
        content = imports + content
    write_file(path, content)
    print("Fixed chat.rs")

def fix_middleware():
    path = f"{SRC}/middleware.rs"
    content = read_file(path)
    # add_cors doesn't exist, remove it from main.rs later
    print("middleware.rs unchanged (log_requests only)")

def fix_handler(path, name, extra_imports=""):
    content = read_file(path)
    if "use axum::" in content or "use crate::" in content:
        print(f"Skipping {name} (already has imports)")
        return

    imports = """use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::{Json, Sse},
    routing::{delete, get, post, put},
};
use std::sync::Arc;
use serde::{Deserialize, Serialize};
use serde_json;
use crate::state::AppState;
use crate::platform::{hermes_home_dir, hermes_binary_path, run_hermes, find_hermes_binary};
use crate::helpers::{read_config, read_file, load_soul_md, oauth_providers, get_active_model, build_chat_messages, strip_think_tags_stream, check_port, classify_provider, ProviderType, get_env_value, save_env_value, get_platform_definitions, universal_cloud_catalog, parse_log_line};
use crate::models::{discover_models, probe_model_via_curl, probe_via_provider, ModelEntry, ModelsResponse};
use crate::chat::{handle_chat, ChatRequest, ChatResponse};
"""
    if extra_imports:
        imports += extra_imports + "\n"

    content = imports + "\n" + content
    write_file(path, content)
    print(f"Fixed {name}")

def main():
    os.chdir("/home/synth/projects/hermes_wingman/backend")
    fix_state()
    fix_platform()
    fix_helpers()
    fix_models()
    fix_chat()
    fix_middleware()

    # Fix all handler files
    for fname in os.listdir(HANDLERS):
        if not fname.endswith(".rs"):
            continue
        if fname == "mod.rs":
            continue
        path = f"{HANDLERS}/{fname}"
        fix_handler(path, fname)

    print("Done fixing imports.")

if __name__ == "__main__":
    main()
