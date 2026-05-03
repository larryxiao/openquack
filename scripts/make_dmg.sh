#!/usr/bin/env bash
# Build a signed DMG of OpenQuack.app, suitable for GitHub Releases +
# Homebrew cask distribution. The bundle inside is signed with whatever
# identity scripts/wrap_app.sh selects (Developer ID for distribution,
# Apple Development for dev iteration, ad-hoc as fallback). Notarisation
# is a separate step that requires Developer ID + an active Apple
# Developer account.
#
# Usage: bash scripts/make_dmg.sh
#        → build/OpenQuack-<version>.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep -E 'public static let version' Sources/OpenQuackPlatform/OpenQuackPlatform.swift | sed -E 's/.*"([^"]+)".*/\1/')"
APP="$ROOT/build/OpenQuack.app"
DMG="$ROOT/build/OpenQuack-$VERSION.dmg"
STAGING="$ROOT/build/dmg-staging"

# Always rebuild + sign the .app first so the DMG never carries a stale
# bundle. wrap_app.sh is fast (incremental SwiftPM build) when nothing
# changed, so this is cheap.
echo "→ Building & signing OpenQuack.app..."
bash "$ROOT/scripts/wrap_app.sh"

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
echo "To cut a release:"
echo "  1. Update the cask sha:"
echo "       sed -i '' \"s|sha256 :no_check|sha256 \\\"$SHA\\\"|\" Casks/openquack.rb"
echo "       (or replace the existing sha256 line if one is already set)"
echo "  2. Commit the cask + tag:"
echo "       git add Casks/openquack.rb && git commit -m 'chore: cask sha for v$VERSION'"
echo "       git tag v$VERSION && git push --tags"
echo "  3. Publish the GitHub Release with the DMG attached:"
echo "       gh release create v$VERSION --title 'OpenQuack $VERSION' '$DMG'"
echo "  4. Verify the install:"
echo "       brew tap larryxiao/openquack https://github.com/larryxiao/openquack"
echo "       brew install --cask openquack"
