#!/usr/bin/env bash
# Build the openquack SwiftPM executable and wrap it in a minimal
# OpenQuack.app bundle under build/.
#
# Signing is picked in this order:
#   1. $OQ_SIGN_IDENTITY (explicit override — usually a Developer ID for dist).
#   2. Any "Developer ID Application: ..." identity in the keychain
#      — distribution cert. Hardened runtime + TSA timestamp + entitlements.
#   3. Any "Apple Development: ..." identity in the keychain (free, comes
#      with Xcode + an Apple ID; no paid Developer Program needed).
#      Gives a stable Designated Requirement → TCC keeps the AX/mic grant
#      across rebuilds. Doesn't satisfy Gatekeeper on other Macs.
#   4. "OpenQuack Dev" if you've created a self-signed code-signing cert
#      with that name. (Keychain Access → Certificate Assistant → Create
#      a Certificate; Self-Signed Root, type Code Signing.) Manual
#      alternative if (3) isn't available.
#   5. Ad-hoc — fallback. Works for local `open`, but each rebuild changes
#      the cdhash so TCC sees a "new" app and re-prompts for permissions.
#
# Usage: bash scripts/wrap_app.sh
#        OQ_SIGN_IDENTITY="Developer ID Application: ..." bash scripts/wrap_app.sh
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
BIN_NAME="openquack"
VERSION="$(grep -E 'public static let version' Sources/OpenQuackKit/OpenQuackKit.swift | sed -E 's/.*"([^"]+)".*/\1/')"

echo "→ Building release..."
swift build -c release --product "$BIN_NAME" >/dev/null

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="$BIN_DIR/$BIN_NAME"
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
cp "$BIN_PATH" "$BUNDLE/Contents/MacOS/openquack"
if [[ -f "$ICON_OUT" ]]; then
    cp "$ICON_OUT" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Copy SwiftPM-generated resource bundles (e.g.
# KeyboardShortcuts_KeyboardShortcuts.bundle) into Resources/. Each module
# that declares `resources:` gets a `<package>_<module>.bundle` next to the
# build product, and Bundle.module — the auto-generated accessor those
# modules use to find their resources at runtime — traps with an
# assertion failure if it can't locate the bundle inside the running .app.
# Symptom: SIGTRAP at launch on Tahoe (macOS 16) the moment any code path
# touches a module with resources (e.g. KeyboardShortcuts.Recorder). Earlier
# macOS versions sometimes accept fallback lookup paths; Tahoe enforces it.
for bundle in "$BIN_DIR"/*.bundle; do
    [[ -d "$bundle" ]] || continue
    cp -R "$bundle" "$BUNDLE/Contents/Resources/"
done

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>            <string>org.openquack.OpenQuack</string>
    <key>CFBundleName</key>                  <string>OpenQuack</string>
    <key>CFBundleDisplayName</key>           <string>OpenQuack</string>
    <key>CFBundleExecutable</key>            <string>openquack</string>
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

ENTITLEMENTS="$ROOT/scripts/openquack.entitlements"

IDENTITY=""
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
pick() {
    # Pull the quoted identity name matching the prefix from `security find-identity`.
    grep -oE "\"$1[^\"]*\"" <<<"$IDENTITIES" | head -1 | tr -d '"'
}

if [[ -n "${OQ_SIGN_IDENTITY:-}" ]]; then
    IDENTITY="$OQ_SIGN_IDENTITY"
elif [[ -n "$(pick 'Developer ID Application: ')" ]]; then
    IDENTITY="$(pick 'Developer ID Application: ')"
elif [[ -n "$(pick 'Apple Development: ')" ]]; then
    IDENTITY="$(pick 'Apple Development: ')"
elif [[ -n "$(pick 'OpenQuack Dev')" ]]; then
    IDENTITY="OpenQuack Dev"
fi

if [[ -n "$IDENTITY" ]]; then
    if [[ "$IDENTITY" == "Developer ID"* ]]; then
        # Distribution cert: hardened runtime + Apple TSA timestamp (required for notarization).
        echo "→ Signing for distribution: $IDENTITY"
        codesign --force --deep --sign "$IDENTITY" \
            --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS" \
            "$BUNDLE"
    else
        # Dev cert (Apple Development / self-signed): stable DR for TCC across
        # rebuilds; no hardened runtime needed (we're not notarizing).
        echo "→ Signing for dev iteration: $IDENTITY"
        codesign --force --deep --sign "$IDENTITY" --timestamp=none "$BUNDLE"
    fi
    DR_LINE="$(codesign -dr - "$BUNDLE" 2>&1 | sed -n 's/^designated => //p')"
    [[ -n "$DR_LINE" ]] && echo "  DR: $DR_LINE"
else
    echo "→ Ad-hoc signing (TCC grants will reset on every rebuild — see header for stable signing options)..."
    codesign --sign - --force --deep --timestamp=none "$BUNDLE" 2>/dev/null || \
        echo "  (codesign skipped)"
fi

echo "✓ $BUNDLE"
echo "  Run with: open $BUNDLE"
