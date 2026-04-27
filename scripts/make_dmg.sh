#!/usr/bin/env bash
# Build an unsigned, ad-hoc-codesigned DMG of OpenQuack.app, suitable for
# distribution via GitHub Releases + Homebrew cask. Notarisation is a
# separate step that requires an Apple Developer account; until then,
# users on first open will need to right-click → Open or accept the
# Gatekeeper prompt once.
#
# Usage: bash scripts/make_dmg.sh
#        → build/OpenQuack-<version>.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep -E 'public static let version' Sources/OpenQuackKit/OpenQuackKit.swift | sed -E 's/.*"([^"]+)".*/\1/')"
APP="$ROOT/build/OpenQuack.app"
DMG="$ROOT/build/OpenQuack-$VERSION.dmg"
STAGING="$ROOT/build/dmg-staging"

# Build the .app first if it isn't there.
if [[ ! -d "$APP" ]]; then
    echo "→ build/OpenQuack.app missing — running wrap_app.sh first..."
    bash "$ROOT/scripts/wrap_app.sh"
fi

echo "→ Staging DMG layout..."
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/OpenQuack.app"

# Drag-to-install convention.
ln -s /Applications "$STAGING/Applications"

echo "→ Creating $DMG..."
hdiutil create \
    -volname "OpenQuack $VERSION" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG" >/dev/null

rm -rf "$STAGING"

# Compute sha256 for the cask formula.
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
SIZE="$(du -h "$DMG" | awk '{print $1}')"

echo
echo "✓ $DMG"
echo "  size:    $SIZE"
echo "  sha256:  $SHA"
echo
echo "Next steps for a real release:"
echo "  1. gh release create v$VERSION --draft \\"
echo "       --title 'OpenQuack $VERSION' \\"
echo "       '$DMG'"
echo "  2. Update Casks/openquack.rb sha256 to:  $SHA"
echo "  3. brew install --cask Casks/openquack.rb  (local install test)"
