#!/usr/bin/env bash
# ─── Hermes Wingman Build Script ─────────────────────────────────────────
# Usage: ./build.sh [linux|macos|windows|all]
# Builds both the Rust backend and the Flutter app for the target platform.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

build_backend() {
  local target="$1"
  echo "▸ Building Rust backend for $target..."

  if [ "$target" = "windows" ]; then
    # Cross-compile for Windows (requires mingw-w64 or similar)
    cargo build --release --target x86_64-pc-windows-gnu 2>/dev/null || \
    cargo build --release --target x86_64-pc-windows-msvc 2>/dev/null || {
      echo "  ⚠ Windows cross-compile not available. Build on a Windows host."
      echo "  cd backend && cargo build --release"
      return 1
    }
  else
    cargo build --release
  fi
  echo "  ✓ Backend built"
}

build_flutter() {
  local target="$1"
  echo "▸ Building Flutter app for $target..."

  flutter pub get

  case "$target" in
    linux)
      flutter build linux --release
      # Copy backend binary into the bundle
      mkdir -p build/linux/x64/release/bundle/
      cp backend/target/release/hermes-wingman-backend build/linux/x64/release/bundle/
      echo "  ✓ Built: build/linux/x64/release/bundle/"

      # ── Deploy to ~/.local/bin/ ──────────────────────────────────
      # Walker shortcut already points to ~/.local/bin/ — this makes
      # every rebuild instantly available without manual copy steps.
      echo "  ▸ Deploying to ~/.local/bin/..."
      mkdir -p "$HOME/.local/bin" "$HOME/.local/bin/lib"
      cp build/linux/x64/release/bundle/hermes_wingman "$HOME/.local/bin/"
      cp -r build/linux/x64/release/bundle/lib/* "$HOME/.local/bin/lib/"
      cp -r build/linux/x64/release/bundle/data/. "$HOME/.local/bin/data/"
      cp backend/target/release/hermes-wingman-backend "$HOME/.local/bin/"
      chmod +x "$HOME/.local/bin/hermes_wingman" "$HOME/.local/bin/hermes-wingman-backend"

      # Keep the desktop entry pointing to the binary directly,
      # forcing X11 backend since Wayland has window sizing issues
      DESKTOP="$HOME/.local/share/applications/hermes-wingman.desktop"
      if [ -f "$DESKTOP" ]; then
        sed -i "s|Exec=.*|Exec=env GDK_BACKEND=x11 ${HOME}/.local/bin/hermes_wingman|" "$DESKTOP"
        echo "  ✓ Desktop entry updated (GDK_BACKEND=x11)"
      fi

      # Package as tar.gz
      bash dist/package.sh --skip-build
      ;;

    macos)
      flutter build macos --release
      # Copy backend binary into the .app bundle
      local app_path="build/macos/Build/Products/Release/hermes_wingman.app"
      local bundle_dir="$app_path/Contents/MacOS"
      mkdir -p "$bundle_dir"
      cp backend/target/release/hermes-wingman-backend "$bundle_dir/"
      echo "  ✓ Built: $app_path"
      echo ""
      echo "To run:"
      echo "  open $app_path"
      echo ""
      echo "To package for distribution:"
      echo "  zip -r hermes-wingman-macos.zip $app_path"
      ;;

    windows)
      flutter build windows --release
      # Locate the backend binary
      local backend_bin="backend/target/x86_64-pc-windows-gnu/release/hermes-wingman-backend.exe"
      [ ! -f "$backend_bin" ] && backend_bin="backend/target/release/hermes-wingman-backend.exe"
      if [ -f "$backend_bin" ]; then
        cp "$backend_bin" build/windows/x64/runner/Release/
      else
        echo "  ⚠ Backend binary not found. Build with: cd backend && cargo build --release"
      fi
      echo "  ✓ Built: build/windows/x64/runner/Release/"
      echo ""
      echo "To run:"
      echo "  build/windows/x64/runner/Release/hermes_wingman.exe"
      ;;

  esac
}

# ─── Main ─────────────────────────────────────────────────────────────────

if [ $# -eq 0 ]; then
  echo "Usage: $0 [linux|macos|windows|all]"
  echo ""
  echo "Builds Hermes Wingman for the specified platform(s)."
  echo "Requires: cargo (Rust), flutter, and platform toolchain."
  echo ""
  echo "  linux   — Build + AppImage tar.gz"
  echo "  macos   — Build + .app bundle"
  echo "  windows — Build + .exe directory"
  echo "  all     — Build all (requires appropriate toolchains)"
  exit 1
fi

target="${1:-}"

case "$target" in
  all)
    build_backend linux && build_flutter linux
    build_backend macos && build_flutter macos
    echo "  ℹ Windows build requires Windows host or cross-compile toolchain"
    echo "     cd backend && cargo build --release (on Windows)"
    ;;

  linux|macos|windows)
    build_backend "$target"
    # On Linux, also build backend for linux (host target)
    if [ "$target" != "linux" ]; then
      cargo build --release 2>/dev/null || true
    fi
    build_flutter "$target"
    ;;

  *)
    echo "Unknown target: $target"
    echo "Usage: $0 [linux|macos|windows|all]"
    exit 1
    ;;
esac

echo ""
echo "🎹🦈  Hermes Wingman built successfully for $target!"
