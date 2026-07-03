#!/bin/bash
# Installs NotchLock to /Applications and launches it. On first launch the app
# registers a per-user LaunchAgent (RunAtLoad) so it survives reboots.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/NotchLock.app"
DEST="/Applications/NotchLock.app"

if [ ! -d "$APP" ]; then
    echo "▶ Building the app first…"
    "$ROOT/scripts/build_app.sh" release
fi

# Stop any running copy (by bundle id) before replacing it.
osascript -e 'quit app "NotchLock"' >/dev/null 2>&1 || true
sleep 1

echo "▶ Installing to $DEST…"
rm -rf "$DEST"
cp -R "$APP" "$DEST"

echo "▶ Launching…"
open "$DEST"

echo "✓ Installed and running. Move the cursor to the notch and pull the cord."
echo "  It now starts automatically at login (right-click the notch to change)."
