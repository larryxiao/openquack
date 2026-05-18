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
VERSION="$(grep -E 'public static let version' Sources/OpenQuackPlatform/OpenQuackPlatform.swift | sed -E 's/.*"([^"]+)".*/\1/')"

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

# Copy SwiftPM-generated resource bundles into Contents/Resources/. The
# install-location fix is in code: BundleModuleFallback.swift swizzles
# Bundle.init(path:) so the SwiftPM-generated Bundle.module accessor's
# first probe — `<App.app>/<name>.bundle`, which codesign forbids — gets
# transparently rewritten to `<App.app>/Contents/Resources/<name>.bundle`
# at runtime. That's where we drop them here, and it works for any
# install location, not just /Applications.
for bundle in "$BIN_DIR"/*.bundle; do
    [[ -d "$bundle" ]] || continue
    cp -R "$bundle" "$BUNDLE/Contents/Resources/"
done

# Copy SwiftPM-resolved frameworks (e.g. Sparkle.framework, a
# .binaryTarget xcframework that lands in the release/ dir alongside the
# binary). They link against `@rpath/<Framework>.framework/...`; the
# binary's default rpath set by SwiftPM (`@loader_path`) finds them in
# the release/ dir but breaks once we move the binary into
# `Contents/MacOS/`. So: copy the framework AND patch the binary's rpath
# to look in `../Frameworks/`.
for fw in "$BIN_DIR"/*.framework; do
    [[ -d "$fw" ]] || continue
    mkdir -p "$BUNDLE/Contents/Frameworks"
    cp -R "$fw" "$BUNDLE/Contents/Frameworks/"
done
if [[ -d "$BUNDLE/Contents/Frameworks" ]]; then
    # `|| true` because install_name_tool errors out on repeat invocations
    # (re-adding an existing rpath). The bundle is rm -rf'd above so this
    # is the first add, but be defensive against future refactors.
    install_name_tool -add_rpath @executable_path/../Frameworks \
        "$BUNDLE/Contents/MacOS/openquack" 2>/dev/null || true
fi

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!--
    SPEC-026 — SUPublicEDKey is intentionally a placeholder. The user
    runs Sparkle's bundled `generate_keys` once locally; the public half
    lands here as a follow-up commit, the private half stays in the
    maintainer's Keychain + a GH Actions secret. Until that swap lands,
    Sparkle fetches the appcast but refuses to install any update — by
    design.
-->
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
    <key>NSAppleEventsUsageDescription</key> <string>OpenQuack uses Terminal to run "brew upgrade --cask openquack" when you click Upgrade.</string>
    <key>NSHumanReadableCopyright</key>      <string>MIT — github.com/larryxiao</string>

    <!-- SPEC-026 — Sparkle 2.x auto-update. Stable channel by default;
         PR-B's Settings toggle will re-point feedURL to the alpha appcast
         at runtime. -->
    <key>SUFeedURL</key>                     <string>https://larryxiao.github.io/openquack/appcast.xml</string>
    <key>SUEnableAutomaticChecks</key>       <true/>
    <key>SUScheduledCheckInterval</key>      <integer>86400</integer>
    <key>SUAutomaticallyUpdate</key>         <false/>
    <key>SUPublicEDKey</key>                 <string>PLACEHOLDER_EDDSA_PUBLIC_KEY_BASE64_REPLACE_ME</string>
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
