#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/Benri.app"
LEGACY_BENRI_APP_DIR="$ROOT_DIR/dist/benri.app"
LEGACY_VALUET_APP_DIR="$ROOT_DIR/dist/valuet.app"
LEGACY_QUICKVAULT_APP_DIR="$ROOT_DIR/dist/QuickVault.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$ROOT_DIR/.build/Benri.iconset"
ICON_FILE="$ROOT_DIR/.build/Benri.icns"

cd "$ROOT_DIR"
swift build -c release --product Benri
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf \
    "$APP_DIR" \
    "$LEGACY_BENRI_APP_DIR" \
    "$LEGACY_VALUET_APP_DIR" \
    "$LEGACY_QUICKVAULT_APP_DIR" \
    "$ICONSET_DIR" \
    "$ICON_FILE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_DIR/Benri" "$MACOS_DIR/Benri"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

swift "$ROOT_DIR/Scripts/generate-icon.swift" \
    "$ICONSET_DIR" \
    "$ROOT_DIR/Resources/benri-icon-source.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
cp "$ICON_FILE" "$RESOURCES_DIR/Benri.icns"

codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
