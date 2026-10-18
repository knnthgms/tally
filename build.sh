#!/bin/bash
# Builds Tally.app into ./build. Pass --install to copy it to /Applications, --run to launch it.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Tally.app"
swift build -c release --product TallyApp
BIN="$(swift build -c release --show-bin-path)/TallyApp"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tally"
cp Support/Info.plist "$APP/Contents/Info.plist"

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
swift Support/make-icon.swift "$ICONSET/icon_1024.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICONSET/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$ICONSET/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
rm "$ICONSET/icon_1024.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP"
echo "Built $APP"

for arg in "$@"; do
  case "$arg" in
    --install) rm -rf "/Applications/Tally.app"; cp -R "$APP" /Applications/; APP="/Applications/Tally.app"; echo "Installed to /Applications";;
    --run) open "$APP";;
  esac
done
