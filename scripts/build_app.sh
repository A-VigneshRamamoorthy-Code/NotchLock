#!/bin/bash
# Builds NotchLock and assembles a double-clickable .app bundle.
# No Xcode required — uses SwiftPM + a hand-written Info.plist.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/NotchLock.app"
BIN_NAME="NotchLock"
MARKETING_VERSION="${MARKETING_VERSION:-1.0.0}"
BUILD_VERSION="${BUILD_VERSION:-1}"

echo "▶ Building ($CONFIG)…"
swift build -c "$CONFIG" --product "$BIN_NAME"
BIN="$(swift build -c "$CONFIG" --product "$BIN_NAME" --show-bin-path)/$BIN_NAME"

echo "▶ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$BIN_NAME"

echo "▶ Generating app icon…"
ICON_PNG="$ROOT/build/AppIcon-1024.png"
ICONSET="$ROOT/build/AppIcon.iconset"
if "$BIN" --appicon "$ICON_PNG" >/dev/null 2>&1; then
    rm -rf "$ICONSET"; mkdir -p "$ICONSET"
    for sz in 16 32 128 256 512; do
        sips -z "$sz" "$sz"         "$ICON_PNG" --out "$ICONSET/icon_${sz}x${sz}.png"    >/dev/null
        sips -z $((sz*2)) $((sz*2)) "$ICON_PNG" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
    done
    if iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
        echo "  ✓ AppIcon.icns"
    else
        echo "  (iconutil unavailable — embedding 1024 PNG as fallback)"
        cp "$ICON_PNG" "$APP/Contents/Resources/AppIcon.png"
    fi
    rm -rf "$ICONSET"
else
    echo "  (icon render failed — skipping)"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>NotchLock</string>
    <key>CFBundleDisplayName</key>          <string>NotchLock</string>
    <key>CFBundleIdentifier</key>           <string>com.notchlock.NotchLock</string>
    <key>CFBundleExecutable</key>           <string>NotchLock</string>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
    <key>CFBundleIconName</key>             <string>AppIcon</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleShortVersionString</key>   <string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key>              <string>${BUILD_VERSION}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <key>NSPrincipalClass</key>             <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <!-- Agent app: no Dock icon, no app menu. -->
    <key>LSUIElement</key>                  <true/>
</dict>
</plist>
PLIST

echo "▶ Ad-hoc code signing…"
codesign --force --sign - --timestamp=none "$APP" 2>/dev/null || echo "  (codesign skipped)"

echo "✓ Built: $APP"
