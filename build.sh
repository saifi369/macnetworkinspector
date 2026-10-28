#!/bin/bash
# Builds Net Inspector and assembles build/Net Inspector.app
#   ./build.sh            build only
#   ./build.sh --run      build and launch
#   ./build.sh --install  build and copy to /Applications (then launch)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Net Inspector"
APP="build/$APP_NAME.app"

echo "▸ Compiling (release)…"
swift build -c release 2>&1 | grep -v '^\[' || true
test -x .build/release/NetInspector

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NetInspector "$APP/Contents/MacOS/NetInspector"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ ! -f build/AppIcon.icns ]]; then
  echo "▸ Rendering app icon…"
  swift scripts/make-icon.swift build >/dev/null
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing (ad-hoc)…"
codesign --force --sign - "$APP" >/dev/null 2>&1

case "${1:-}" in
  --install)
    echo "▸ Installing to /Applications"
    pkill -x NetInspector 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    open "/Applications/$APP_NAME.app"
    ;;
  --run)
    pkill -x NetInspector 2>/dev/null || true
    open "$APP"
    ;;
esac
echo "✓ Done: $APP"
