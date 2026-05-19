#!/bin/bash
# ─── Hermes Wingman Installer ────────────────────────────────────────────
# Usage: ./install.sh [--prefix ~/.local]
set -e

PREFIX="${1:-$HOME/.local}"
BINDIR="$PREFIX/bin"
APPDIR="$PREFIX/share/applications"
ICONDIR="$PREFIX/share/icons/hicolor/256x256/apps"
SYSTEMD_DIR="$HOME/.config/systemd/user"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Hermes Wingman to $PREFIX..."

# Find the AppDir (either alongside this script or in the dist directory)
APP_DIR=""
if [ -d "$SCRIPT_DIR/AppDir/usr/bin" ]; then
  APP_DIR="$SCRIPT_DIR/AppDir"
elif [ -f "$SCRIPT_DIR/../AppRun" ]; then
  APP_DIR="$SCRIPT_DIR"
elif [ -d "$SCRIPT_DIR/../dist/AppDir" ]; then
  APP_DIR="$SCRIPT_DIR/../dist/AppDir"
else
  echo "ERROR: Cannot find AppDir. Run this script from the dist/ directory."
  exit 1
fi

mkdir -p "$BINDIR" "$APPDIR" "$ICONDIR" "$SYSTEMD_DIR"

# Copy binaries
cp "$APP_DIR/usr/bin/hermes_wingman" "$BINDIR/"
cp "$APP_DIR/usr/bin/hermes-wingman-backend" "$BINDIR/"
chmod +x "$BINDIR/hermes_wingman" "$BINDIR/hermes-wingman-backend"

# Libraries
mkdir -p "$PREFIX/lib/hermes-wingman"
cp -r "$APP_DIR/usr/bin/lib/"* "$PREFIX/lib/hermes-wingman/"

# Desktop entry
cp "$APP_DIR/hermes-wingman.desktop" "$APPDIR/"
sed -i "s|Exec=.*|Exec=$BINDIR/hermes_wingman|" "$APPDIR/hermes-wingman.desktop"

# Icon
if [ -f "$APP_DIR/hermes-wingman.png" ]; then
  cp "$APP_DIR/hermes-wingman.png" "$ICONDIR/"
fi

# Systemd user service for backend
cat > "$SYSTEMD_DIR/hermes-wingman.service" << 'SERVICE'
[Unit]
Description=Hermes Wingman Backend
After=network.target

[Service]
Type=simple
ExecStart=%h/.local/bin/hermes-wingman-backend
Restart=on-failure
RestartSec=3
Environment=PAGER=cat

[Install]
WantedBy=default.target
SERVICE

systemctl --user daemon-reload 2>/dev/null || true

echo ""
echo "✓ Installed to $BINDIR/"
echo "✓ Desktop entry: $APPDIR/hermes-wingman.desktop"
echo ""
echo "To start the backend service automatically:"
echo "  systemctl --user enable --now hermes-wingman"
echo ""
echo "Then run:"
echo "  hermes_wingman"
echo ""
echo "Make sure $BINDIR is in your PATH!"
