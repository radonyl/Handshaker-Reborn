#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/ADB Pull Photos.app"
CONTENTS="$APP_DIR/Contents"
DMG="${1:-$HOME/Desktop/ADB Pull Photos.dmg}"

ADB_SOURCE="${ADB_SOURCE:-}"
if [[ -z "$ADB_SOURCE" ]]; then
  ADB_SOURCE="$(command -v adb || true)"
fi

if [[ -z "$ADB_SOURCE" || ! -x "$ADB_SOURCE" ]]; then
  echo "error: adb not found. Install android-platform-tools or set ADB_SOURCE=/path/to/adb." >&2
  exit 1
fi

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/cfg" "$CONTENTS/Resources/platform-tools"

cp "$ROOT_DIR/.build/release/ADBPullPhotos" "$CONTENTS/MacOS/ADBPullPhotos"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT_DIR/cfg/pull_camera.ini" "$CONTENTS/Resources/cfg/pull_camera.ini"
cp "$ADB_SOURCE" "$CONTENTS/Resources/platform-tools/adb"

chmod +x "$CONTENTS/MacOS/ADBPullPhotos"
chmod +x "$CONTENTS/Resources/platform-tools/adb"

codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

rm -f "$DMG"
hdiutil create -volname "ADB Pull Photos" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"
ls -lh "$DMG"
