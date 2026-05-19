#!/usr/bin/env bash
# ─── Hermes Wingman Packaging Script ──────────────────────────────────────
# Builds everything and creates a distribution archive.
# Usage: ./dist/package.sh [--skip-build]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$SCRIPT_DIR"
BUILD_DIR="$PROJECT_DIR/build/linux/x64/release/bundle"
APP_DIR="$DIST_DIR/AppDir"
VERSION="${VERSION:-0.1.0}"
ARCH="$(uname -m)"
PKG_NAME="hermes-wingman-${VERSION}-linux-${ARCH}"

echo "🎹🦞  Hermes Wingman Packager"
echo ""

# ─── Build ────────────────────────────────────────────────────────────────
if [ "${1:-}" != "--skip-build" ]; then
  echo "▸ Building Rust backend..."
  cd "$PROJECT_DIR/backend"
  cargo build --release
  echo "  ✓ Backend built"

  echo "▸ Building Flutter app..."
  cd "$PROJECT_DIR"
  flutter build linux --release
  echo "  ✓ Flutter app built"
else
  echo "▸ Skipping build (--skip-build)"
fi

# ─── Verify build artifacts ──────────────────────────────────────────────
if [ ! -f "$BUILD_DIR/hermes_wingman" ]; then
  echo "ERROR: Flutter binary not found at $BUILD_DIR/hermes_wingman"
  echo "Run 'flutter build linux --release' first."
  exit 1
fi

if [ ! -f "$PROJECT_DIR/backend/target/release/hermes-wingman-backend" ]; then
  echo "ERROR: Backend binary not found. Run 'cargo build --release' in backend/."
  exit 1
fi

# ─── Clean and prepare AppDir ────────────────────────────────────────────
echo "▸ Preparing AppDir..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/usr/bin/data"
mkdir -p "$APP_DIR/usr/bin/lib"

# Copy Flutter app
cp -r "$BUILD_DIR/data/flutter_assets" "$APP_DIR/usr/bin/data/"
cp "$BUILD_DIR/data/icudtl.dat" "$APP_DIR/usr/bin/data/"
cp "$BUILD_DIR/hermes_wingman" "$APP_DIR/usr/bin/"
cp "$BUILD_DIR/lib/libapp.so" "$APP_DIR/usr/bin/lib/"
cp "$BUILD_DIR/lib/libdartjni.so" "$APP_DIR/usr/bin/lib/"
cp "$BUILD_DIR/lib/libflutter_linux_gtk.so" "$APP_DIR/usr/bin/lib/"

# Copy backend binary
cp "$PROJECT_DIR/backend/target/release/hermes-wingman-backend" "$APP_DIR/usr/bin/"

# Generate PNG icon from SVG
if command -v rsvg-convert &>/dev/null; then
  rsvg-convert -w 256 -h 256 "$PROJECT_DIR/assets/icons/hermes-wingman.svg" -o "$APP_DIR/hermes-wingman.png"
elif command -v convert &>/dev/null; then
  convert -background none -size 256x256 "$PROJECT_DIR/assets/icons/hermes-wingman.svg" "$APP_DIR/hermes-wingman.png"
else
  # Placeholder — copy the SVG and let the system handle it
  cp "$PROJECT_DIR/assets/icons/hermes-wingman.svg" "$APP_DIR/hermes-wingman.svg"
fi

# ─── AppRun entry point ───────────────────────────────────────────────────
cat > "$APP_DIR/AppRun" << 'APPRUN'
#!/bin/bash
# Hermes Wingman AppRun — portable entry point
HERE="$(dirname "$(readlink -f "$0")")"
export PATH="$HERE/usr/bin:$PATH"
export LD_LIBRARY_PATH="$HERE/usr/bin/lib:$LD_LIBRARY_PATH"

# Start backend in background
"$HERE/usr/bin/hermes-wingman-backend" &
BACKEND_PID=$!

# Wait for backend to be ready
for i in $(seq 1 20); do
  if curl -s http://127.0.0.1:9120/health > /dev/null 2>&1; then
    break
  fi
  sleep 0.3
done

# Launch the Flutter app
cd "$HERE/usr/bin"
exec ./hermes_wingman "$@"
APPRUN
chmod +x "$APP_DIR/AppRun"

# ─── Desktop file ─────────────────────────────────────────────────────────
cat > "$APP_DIR/hermes-wingman.desktop" << DESKTOP
[Desktop Entry]
Name=Hermes Wingman
Comment=Universal GUI for Hermes Agent
Exec=AppRun
Icon=hermes-wingman
Type=Application
Categories=Utility;Development;AI;
Terminal=false
StartupWMClass=hermes_wingman
X-AppImage-Version=${VERSION}
DESKTOP

# ─── Create .tar.gz archive ───────────────────────────────────────────────
echo "▸ Creating archive..."
cd "$DIST_DIR"
tar czf "${PKG_NAME}.tar.gz" \
  --transform="s|^AppDir|${PKG_NAME}|" \
  AppDir/

echo ""
echo "✓ Package created: dist/${PKG_NAME}.tar.gz"
echo "  Size: $(du -h "${PKG_NAME}.tar.gz" | cut -f1)"
echo ""
echo "To install:"
echo "  tar xzf ${PKG_NAME}.tar.gz"
echo "  cd ${PKG_NAME}"
echo "  ./AppRun"
echo ""
echo "Or system-wide install:"
echo "  mkdir -p ~/.local/bin"
echo "  cp ${PKG_NAME}/usr/bin/hermes_wingman ~/.local/bin/"
echo "  cp ${PKG_NAME}/usr/bin/hermes-wingman-backend ~/.local/bin/"
echo "  cp ${PKG_NAME}/hermes-wingman.desktop ~/.local/share/applications/"
