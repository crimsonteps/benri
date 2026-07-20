#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/valuet.app"
LEGACY_APP_DIR="$ROOT_DIR/dist/QuickVault.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$ROOT_DIR/.build/valuet.iconset"
ICON_FILE="$ROOT_DIR/.build/valuet.icns"

cd "$ROOT_DIR"
swift build -c release --product valuet
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR" "$LEGACY_APP_DIR" "$ICONSET_DIR" "$ICON_FILE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_DIR/valuet" "$MACOS_DIR/valuet"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

swift "$ROOT_DIR/Scripts/generate-icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
cp "$ICON_FILE" "$RESOURCES_DIR/valuet.icns"

codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
