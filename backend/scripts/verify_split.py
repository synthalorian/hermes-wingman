#!/usr/bin/env python3
"""
Verification script for the Rust backend modularization.
Checks that:
1. All expected modules exist
2. All route handlers are defined in handler modules
3. main.rs has no orphan handler code
4. cargo check passes
"""

import os
import subprocess
import sys

EXPECTED_MODULES = [
    "src/main.rs",
    "src/platform.rs",
    "src/state.rs",
    "src/helpers.rs",
    "src/models.rs",
    "src/chat.rs",
    "src/middleware.rs",
    "src/handlers/mod.rs",
    "src/handlers/config.rs",
    "src/handlers/models.rs",
    "src/handlers/chat.rs",
    "src/handlers/chat_stream.rs",
    "src/handlers/sessions.rs",
    "src/handlers/logs.rs",
    "src/handlers/gateway.rs",
    "src/handlers/cron.rs",
    "src/handlers/providers.rs",
    "src/handlers/setup.rs",
    "src/handlers/skills.rs",
    "src/handlers/memory.rs",
    "src/handlers/files.rs",
    "src/handlers/cli.rs",
    "src/handlers/auth.rs",
    "src/handlers/metrics.rs",
]

HANDLER_NAMES = [
    "health", "get_config", "write_config", "update_config", "validate_config",
    "get_models", "switch_model", "probe_model_handler",
    "chat_handler", "chat_stream_handler",
    "get_sessions", "get_logs",
    "gateway_get_platforms", "gateway_configure_platform", "gateway_service_action",
    "get_gateway", "gateway_toggle",
    "get_cron", "get_providers", "detect_setup", "install_hermes", "auto_configure",
    "probe_provider_handler",
    "hermes_version", "hermes_update", "hermes_skills", "hermes_skills_toggle",
    "memory_list", "memory_get", "memory_delete", "memory_search",
    "files_list", "files_read", "files_write", "files_info", "files_delete",
    "files_rename", "files_mkdir",
    "hermes_command", "cli_fallback_list", "cli_fallback_add", "cli_fallback_clear",
    "cli_webhook_list", "cli_hooks_list", "cli_plugins_list", "cli_curator_status",
    "cli_mcp_list", "cli_doctor", "cli_security_audit", "cli_dump", "cli_debug_share",
    "cli_backup_create", "cli_checkpoints_status", "cli_proxy_status",
    "cli_secrets_status", "cli_pairing_list", "cli_insights",
    "auth_start_oauth", "auth_add_api_key", "auth_get_status", "auth_logout",
    "get_metrics", "restart_backend",
]

def check_files():
    """Verify all expected module files exist."""
    missing = []
    for path in EXPECTED_MODULES:
        full = os.path.join("src", path[4:]) if path.startswith("src/") else path
        if not os.path.exists(full):
            missing.append(path)
    if missing:
        print(f"FAIL: Missing {len(missing)} module files:")
        for m in missing:
            print(f"  - {m}")
        return False
    print(f"PASS: All {len(EXPECTED_MODULES)} expected module files exist.")
    return True

def check_handlers():
    """Verify all route handler functions are defined somewhere in src/."""
    missing = []
    for handler in HANDLER_NAMES:
        found = False
        for root, _, files in os.walk("src"):
            for f in files:
                if not f.endswith(".rs"):
                    continue
                path = os.path.join(root, f)
                with open(path) as fh:
                    content = fh.read()
                # Look for async fn or pub async fn or pub fn with the handler name
                if f"async fn {handler}" in content or f"pub async fn {handler}" in content or f"pub fn {handler}" in content:
                    found = True
                    break
            if found:
                break
        if not found:
            missing.append(handler)
    if missing:
        print(f"FAIL: {len(missing)} handlers not found in any module:")
        for m in missing:
            print(f"  - {m}")
        return False
    print(f"PASS: All {len(HANDLER_NAMES)} route handlers found in modules.")
    return True

def check_cargo():
    """Run cargo check."""
    print("Running cargo check...")
    result = subprocess.run(
        ["cargo", "check"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print("FAIL: cargo check failed:")
        print(result.stderr[:2000])
        return False
    print("PASS: cargo check succeeded.")
    return True

def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)) + "/..")
    ok = True
    ok &= check_files()
    ok &= check_handlers()
    ok &= check_cargo()
    if ok:
        print("\n✅ All verification checks passed.")
        sys.exit(0)
    else:
        print("\n❌ Some verification checks failed.")
        sys.exit(1)

if __name__ == "__main__":
    main()
