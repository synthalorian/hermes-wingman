import os, re

os.chdir("/home/synth/projects/hermes_wingman/backend/src")

def read(path):
    with open(path) as f:
        return f.read()

def write(path, content):
    with open(path, "w") as f:
        f.write(content)

# 1. Make every fn / struct / enum in core modules pub
for fname in ["platform.rs", "helpers.rs", "models.rs", "chat.rs", "state.rs", "middleware.rs"]:
    content = read(fname)
    # fn -> pub fn (but not if already pub)
    content = re.sub(r'^(?!\s*pub\s)(\s*)(async\s+)?fn\s+', r'\1pub \2fn ', content, flags=re.MULTILINE)
    content = re.sub(r'^(?!\s*pub\s)(\s*)struct\s+', r'\1pub struct ', content, flags=re.MULTILINE)
    content = re.sub(r'^(?!\s*pub\s)(\s*)enum\s+', r'\1pub enum ', content, flags=re.MULTILINE)
    write(fname, content)
    print(f"Made items pub in {fname}")

# 2. Move check_port and strip_think_tags_stream from setup.rs to helpers.rs
setup = read("handlers/setup.rs")
helpers = read("helpers.rs")

# Extract the two functions
for func_name in ["check_port", "strip_think_tags_stream"]:
    pattern = rf'(//|/\*)?[^\n]*{func_name}[^\n]*\n(?:pub\s+)?fn\s+{func_name}\([^}}]+\}}\n\n?'
    m = re.search(pattern, setup, re.DOTALL)
    if m:
        func_code = m.group(0)
        setup = setup.replace(func_code, "")
        if func_code not in helpers:
            helpers += "\n" + func_code
        print(f"Moved {func_name} to helpers.rs")

write("handlers/setup.rs", setup)
write("helpers.rs", helpers)

# 3. Fix chat_stream.rs — remove strip_think_tags_stream from crate::helpers import,
#    and fix Stream/Event imports
chat_stream = read("handlers/chat_stream.rs")
chat_stream = chat_stream.replace("strip_think_tags_stream, ", "")
chat_stream = chat_stream.replace(", strip_think_tags_stream", "")
# Add missing imports for Stream/Event if not present
if "use futures::StreamExt;" not in chat_stream and "use futures::" not in chat_stream:
    # Insert after the axum import block
    chat_stream = chat_stream.replace(
        "use crate::chat::{handle_chat, ChatRequest, ChatResponse};",
        "use crate::chat::{handle_chat, ChatRequest, ChatResponse};\nuse futures::StreamExt;"
    )
write("handlers/chat_stream.rs", chat_stream)
print("Fixed chat_stream.rs imports")

# 4. Fix cli.rs — remove duplicate Json import, fix Deserialize
cli = read("handlers/cli.rs")
cli = cli.replace("use axum::{extract::Json, http::StatusCode, response::Json};",
                   "use axum::{extract::Json as ExtractJson, http::StatusCode, response::Json};")
# Fix HermesCommandBody Json usage
cli = cli.replace("Json(body): Json<HermesCommandBody>", "ExtractJson(body): ExtractJson<HermesCommandBody>")
# Fix other cli functions that don't use Json extract but use response Json
# Actually, simpler: just remove the ExtractJson alias and use Json for response only
cli = cli.replace("use axum::{extract::Json as ExtractJson, http::StatusCode, response::Json};",
                   "use axum::{http::StatusCode, response::Json};")
cli = cli.replace("ExtractJson(body): ExtractJson<HermesCommandBody>", "Json(body): Json<HermesCommandBody>")
# Add serde Deserialize back
if "use serde::" not in cli:
    cli = "use serde::Deserialize;\n" + cli
write("handlers/cli.rs", cli)
print("Fixed cli.rs imports")

# 5. Make all async fn handlers pub in all handler files
for fname in os.listdir("handlers"):
    if not fname.endswith(".rs") or fname == "mod.rs":
        continue
    path = f"handlers/{fname}"
    content = read(path)
    # Make async fn handlers pub
    content = re.sub(r'^(?!\s*pub\s)(\s*)async\s+fn\s+', r'\1pub async fn ', content, flags=re.MULTILINE)
    # Make regular fn handlers pub too
    content = re.sub(r'^(?!\s*pub\s)(\s*//[^\n]*\n)?(\s*)fn\s+(get_|save_|parse_|resolve_|detect_|check_|strip_|build_|probe_|classify_|load_|read_|oauth_|hermes_home_dir|find_hermes_binary|hermes_binary_path|run_hermes|universal_cloud_catalog)',
                     r'\1\2pub fn \3', content, flags=re.MULTILINE)
    write(path, content)
    print(f"Made handlers pub in {fname}")

print("Done polishing modules!")
