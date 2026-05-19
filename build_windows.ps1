# ─── Hermes Wingman Windows Build Script ─────────────────────────────────
# Usage: .\build_windows.ps1
# Builds both the Rust backend and the Flutter app for Windows.
# Requires: Rust (cargo), Flutter SDK, Visual Studio Build Tools

Write-Host "🎹🦞  Building Hermes Wingman for Windows..." -ForegroundColor Cyan

# 1. Build Rust backend
Write-Host "▸ Building Rust backend..." -ForegroundColor Yellow
Set-Location backend
cargo build --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Backend build failed" -ForegroundColor Red
    exit 1
}
Set-Location ..

# 2. Build Flutter app
Write-Host "▸ Building Flutter app..." -ForegroundColor Yellow
flutter pub get
flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Flutter build failed" -ForegroundColor Red
    exit 1
}

# 3. Copy backend into bundle
Write-Host "▸ Copying backend binary..." -ForegroundColor Yellow
$backendBin = "backend\target\release\hermes-wingman-backend.exe"
$bundleDir = "build\windows\x64\runner\Release"

if (Test-Path $backendBin) {
    Copy-Item $backendBin -Destination $bundleDir
    Write-Host "  ✓ Backend copied" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Backend binary not found at $backendBin" -ForegroundColor Red
    exit 1
}

# 4. Copy icon (for shortcut creation)
$iconSrc = "assets\icons\hermes-wingman.png"
if (Test-Path $iconSrc) {
    Copy-Item $iconSrc -Destination $bundleDir
}

Write-Host ""
Write-Host "✓ Build complete!" -ForegroundColor Green
Write-Host ""
Write-Host "To run:" -ForegroundColor White
Write-Host "  $bundleDir\hermes_wingman.exe" -ForegroundColor Cyan
Write-Host ""
Write-Host "To create a desktop shortcut:" -ForegroundColor White
Write-Host "  Right-click hermes_wingman.exe → Send to → Desktop (create shortcut)" -ForegroundColor DarkGray
