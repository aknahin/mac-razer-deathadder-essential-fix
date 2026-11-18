#!/bin/bash
# Builds "DeathAdder Fix.app" (universal: Apple silicon + Intel) into ./dist.
# Double-clicking the app starts the local helper and opens the UI in your browser.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="DeathAdder Fix"
BUNDLE_ID="io.github.aknahin.deathadder-fix"
VERSION="${VERSION:-1.0.0}"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "→ Building release binary"
ARCHS=(--arch arm64 --arch x86_64)
if ! swift build -c release "${ARCHS[@]}" >/dev/null 2>&1; then
  echo "  (universal build unavailable, building for this Mac only)"
  ARCHS=()
  swift build -c release
fi
BIN_DIR="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/deathadder-fix" "$APP/Contents/MacOS/deathadder-fix"
cp -R Sources/deathadder-fix/Web "$APP/Contents/Resources/Web"

# Launcher: start the helper, which opens the UI in the browser. Opening the app
# again while it runs is delivered to the helper as a reopen event (see AppDelegate).
cat > "$APP/Contents/MacOS/launcher" <<'SH'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
# A helper left over from a crash would hold the port; replace it.
pkill -f "$DIR/deathadder-fix serve" 2>/dev/null && sleep 0.3
exec "$DIR/deathadder-fix" serve
SH
chmod +x "$APP/Contents/MacOS/launcher"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>launcher</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License. Not affiliated with Razer Inc.</string>
</dict>
</plist>
PLIST

echo "→ Rendering icon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 64 128 256 512 1024; do
  sips -s format png -z $size $size scripts/icon.png --out "$ICONSET/icon_${size}.png" >/dev/null 2>&1 || true
done
if [ -f "$ICONSET/icon_1024.png" ]; then
  cp "$ICONSET/icon_16.png" "$ICONSET/icon_16x16.png"
  cp "$ICONSET/icon_32.png" "$ICONSET/icon_16x16@2x.png"
  cp "$ICONSET/icon_32.png" "$ICONSET/icon_32x32.png"
  cp "$ICONSET/icon_64.png" "$ICONSET/icon_32x32@2x.png"
  cp "$ICONSET/icon_128.png" "$ICONSET/icon_128x128.png"
  cp "$ICONSET/icon_256.png" "$ICONSET/icon_128x128@2x.png"
  cp "$ICONSET/icon_256.png" "$ICONSET/icon_256x256.png"
  cp "$ICONSET/icon_512.png" "$ICONSET/icon_256x256@2x.png"
  cp "$ICONSET/icon_512.png" "$ICONSET/icon_512x512.png"
  cp "$ICONSET/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
  rm "$ICONSET"/icon_{16,32,64,128,256,512,1024}.png
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

echo "→ Ad-hoc signing"
codesign --force --deep --sign - "$APP" >/dev/null

echo "→ Zipping"
(cd "$DIST" && rm -f "$APP_NAME.zip" && ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip")

echo "✓ Built $APP and $DIST/$APP_NAME.zip"
