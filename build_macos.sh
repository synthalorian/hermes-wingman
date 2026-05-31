#!/bin/bash
# ─── Hermes Wingman macOS Build Script ───────────────────────────────────
# Usage: ./build_macos.sh
# Builds the Rust backend + Flutter app and creates a distributable .app.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🎹🦈  Building Hermes Wingman for macOS..."

# 1. Build Rust backend
echo "▸ Building Rust backend..."
cd backend
cargo build --release
cd ..
echo "  ✓ Backend built"

# 2. Build Flutter app
echo "▸ Building Flutter app..."
flutter pub get
flutter build macos --release
echo "  ✓ Flutter app built"

# 3. Copy backend into .app bundle
APP_PATH="build/macos/Build/Products/Release/hermes_wingman.app"
BUNDLE_DIR="$APP_PATH/Contents/MacOS"

if [ ! -d "$APP_PATH" ]; then
    echo "✗ .app bundle not found at $APP_PATH"
    exit 1
fi

echo "▸ Copying backend into .app bundle..."
mkdir -p "$BUNDLE_DIR"
cp backend/target/release/hermes-wingman-backend "$BUNDLE_DIR/"
echo "  ✓ Backend copied to $BUNDLE_DIR/"

# 4. Generate app icon from SVG (if tools available)
if command -v iconutil &>/dev/null && command -v rsvg-convert &>/dev/null; then
    echo "▸ Generating app icon..."
    mkdir -p /tmp/hermes-icon.iconset
    for size in 16 32 64 128 256 512; do
        rsvg-convert -w $size -h $size assets/icons/hermes-wingman.svg \
            -o "/tmp/hermes-icon.iconset/icon_${size}x${size}.png"
        if [ $size -lt 512 ]; then
            rsvg-convert -w $((size*2)) -h $((size*2)) assets/icons/hermes-wingman.svg \
                -o "/tmp/hermes-icon.iconset/icon_${size}x${size}@2x.png"
        fi
    done
    iconutil -c icns /tmp/hermes-icon.iconset -o "$APP_PATH/Contents/Resources/hermes-wingman.icns"
    rm -rf /tmp/hermes-icon.iconset
    # Update Info.plist to point to the icon
    plutil -replace CFBundleIconFile -string "hermes-wingman" "$APP_PATH/Contents/Info.plist"
    echo "  ✓ App icon generated"
fi

# 5. Create distribution zip
echo "▸ Creating distribution archive..."
ZIP_NAME="hermes-wingman-macos.zip"
cd build/macos/Build/Products/Release/
rm -f "$SCRIPT_DIR/$ZIP_NAME"
zip -r "$SCRIPT_DIR/$ZIP_NAME" hermes_wingman.app > /dev/null 2>&1
cd "$SCRIPT_DIR"
echo "  ✓ Created: $ZIP_NAME ($(du -h "$ZIP_NAME" | cut -f1))"

echo ""
echo "✓ Build complete!"
echo ""
echo "To run:"
echo "  open $APP_PATH"
echo ""
echo "To distribute:"
echo "  $ZIP_NAME"
echo ""
echo "Users just unzip and drag hermes_wingman.app to their Applications folder."
