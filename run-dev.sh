#!/bin/bash
# Sign + launch for dev builds.
# Uses the "EVE Imager Dev" self-signed cert if set up via setup-codesign.sh.
# Run with --rebuild to do a full cmake rebuild first.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$SCRIPT_DIR/build/eve-imager.app"
IDENTITY="EVE Imager Dev"

sign_app() {
  echo "Cleaning broken symlinks..."
  find "$APP" -type l ! -exec test -e {} \; -delete 2>/dev/null || true
  echo "Clearing quarantine attributes..."
  xattr -cr "$APP" 2>/dev/null || true
  echo "Signing..."
  codesign --deep --force --sign "$IDENTITY" --timestamp=none "$APP"
}

if [ "$1" = "--rebuild" ]; then
  # Auto-detect Qt location
  QT_ROOT=$(brew --prefix qt 2>/dev/null || echo "/opt/homebrew/opt/qt")
  ARCH=$(uname -m)  # arm64 or x86_64
  echo "Rebuilding (Qt: $QT_ROOT, arch: $ARCH)..."
  cmake -B "$SCRIPT_DIR/build" -S "$SCRIPT_DIR/src" \
    -DCMAKE_BUILD_TYPE=Release \
    -DQt6_ROOT="$QT_ROOT" \
    -DCMAKE_PREFIX_PATH="$QT_ROOT" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH"
  cmake --build "$SCRIPT_DIR/build" -j$(sysctl -n hw.ncpu)
  # cmake post-build already signs — just launch
  pkill -x "eve-imager" 2>/dev/null; sleep 0.3
  open "$APP"
  exit 0
fi

if [ ! -d "$APP" ]; then
  echo "ERROR: $APP not found — run: ./run-dev.sh --rebuild"
  exit 1
fi

sign_app
echo "Launching..."
pkill -x "eve-imager" 2>/dev/null; sleep 0.3
open "$APP"
