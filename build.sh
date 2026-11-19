#!/bin/bash
# Builds OnePlusBuds.app (needs Xcode or Command Line Tools: xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/OnePlusBuds"

APP="OnePlusBuds.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OnePlusBuds"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Icon: icon.png -> AppIcon.icns
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# --- WidgetKit extension (built by hand with swiftc, no Xcode project needed)
APPEX="$APP/Contents/PlugIns/OnePlusBudsWidget.appex"
mkdir -p "$APPEX/Contents/MacOS"
if swiftc -O -parse-as-library -application-extension \
    -target arm64-apple-macos14.0 \
    -framework WidgetKit -framework SwiftUI \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$APPEX/Contents/MacOS/OnePlusBudsWidget" \
    Widget/OnePlusBudsWidget.swift Sources/OnePlusBuds/WidgetShared.swift; then
  cp Widget/Info.plist "$APPEX/Contents/Info.plist"
  codesign --force --sign - --entitlements Widget/Widget.entitlements "$APPEX"
else
  echo "WARNING: widget extension failed to compile - app built without widget"
  rm -rf "$APP/Contents/PlugIns"
fi

# Ad-hoc signature so macOS lets the app use Bluetooth and show notifications
codesign --force --sign - "$APP"

# Shared folder the widget reads from
mkdir -p /Users/Shared/OnePlusBuds && chmod 777 /Users/Shared/OnePlusBuds 2>/dev/null || true

# Install into ~/Applications so the widget gallery picks it up, and register it
DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -x OnePlusBuds 2>/dev/null || true
rm -rf "$DEST/$APP"
cp -R "$APP" "$DEST/$APP"
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSR" -f "$DEST/$APP" >/dev/null 2>&1 || true
pluginkit -a "$DEST/$APP/Contents/PlugIns/OnePlusBudsWidget.appex" 2>/dev/null || true
touch "$DEST/$APP"

echo "Done: $DEST/$APP"
echo "Run:  open $DEST/$APP"
