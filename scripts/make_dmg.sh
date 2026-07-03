#!/bin/bash
# Builds a drag-to-install NotchLock.dmg from the assembled .app bundle.
# Uses only built-in hdiutil (no Homebrew / create-dmg needed).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/NotchLock.app"
DMG="$ROOT/NotchLock.dmg"
VOL="NotchLock"
STAGE="$ROOT/build/dmg-stage"

if [ ! -d "$APP" ]; then
    echo "✗ $APP not found — run scripts/build_app.sh first."
    exit 1
fi

echo "▶ Staging…"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag-to-install target

echo "▶ Building DMG…"
hdiutil create \
    -volname "$VOL" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

rm -rf "$STAGE"
SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo "✓ Built: $DMG ($SIZE)"
