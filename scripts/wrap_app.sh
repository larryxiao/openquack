#!/usr/bin/env bash
# Build the openquack-app SwiftPM executable and wrap it in a minimal
# OpenQuack.app bundle under build/. Output is unsigned — fine for local
# `open`; signing/notarisation lives in M3 (SPEC TBD).
#
# Usage: bash scripts/wrap_app.sh
#        open build/OpenQuack.app
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Some deps (KeyboardShortcuts, etc.) include `#Preview` blocks that need the
# PreviewsMacros plugin which only ships with full Xcode. If `xcode-select`
# is pointing at CommandLineTools, force Xcode for this build.
if [[ "$(xcode-select -p)" == *CommandLineTools* ]] && [[ -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    echo "→ Using Xcode toolchain at $DEVELOPER_DIR"
fi

BUNDLE="$ROOT/build/OpenQuack.app"
BIN_NAME="openquack-app"
VERSION="$(grep -E 'public static let version' Sources/OpenQuackKit/OpenQuackKit.swift | sed -E 's/.*"([^"]+)".*/\1/')"

echo "→ Building release..."
swift build -c release --product "$BIN_NAME" >/dev/null

BIN_PATH="$(swift build -c release --show-bin-path)/$BIN_NAME"
[[ -x "$BIN_PATH" ]] || { echo "error: built binary not found at $BIN_PATH" >&2; exit 1; }

# Regenerate the procedural app icon if missing or stale relative to its source.
ICON_OUT="$ROOT/build/AppIcon.icns"
ICON_SRC="$ROOT/scripts/make_icon.swift"
if [[ ! -f "$ICON_OUT" ]] || [[ "$ICON_SRC" -nt "$ICON_OUT" ]]; then
    echo "→ Generating AppIcon.icns..."
    swift "$ICON_SRC"
fi

echo "→ Assembling $BUNDLE (v$VERSION)..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$BUNDLE/Contents/MacOS/openquack-app"
if [[ -f "$ICON_OUT" ]]; then
    cp "$ICON_OUT" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>            <string>org.openquack.OpenQuack</string>
    <key>CFBundleName</key>                  <string>OpenQuack</string>
    <key>CFBundleDisplayName</key>           <string>OpenQuack</string>
    <key>CFBundleExecutable</key>            <string>openquack-app</string>
    <key>CFBundleIconFile</key>              <string>AppIcon</string>
    <key>CFBundleVersion</key>               <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>    <string>$VERSION</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>LSMinimumSystemVersion</key>        <string>13.0</string>
    <key>LSUIElement</key>                   <true/>
    <key>NSPrincipalClass</key>              <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>NSMicrophoneUsageDescription</key>  <string>OpenQuack transcribes your voice locally to dispatch commands to your AI agent. Audio never leaves the machine.</string>
    <key>NSHumanReadableCopyright</key>      <string>MIT — github.com/OpenQuack</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS lets us launch without Gatekeeper barking on first open.
codesign --sign - --force --deep --timestamp=none "$BUNDLE" 2>/dev/null || \
    echo "  (codesign skipped — set up signing in M3)"

echo "✓ $BUNDLE"
echo "  Run with: open $BUNDLE"
