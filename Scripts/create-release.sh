#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
APP_DIR="$ROOT_DIR/dist/Benri.app"
ZIP_NAME="Benri-v$VERSION-macOS-universal.zip"
ZIP_PATH="$ROOT_DIR/dist/$ZIP_NAME"
CHECKSUM_PATH="$ZIP_PATH.sha256"

cd "$ROOT_DIR"
BENRI_ARCHS="${BENRI_ARCHS:-arm64 x86_64}" ./Scripts/package-app.sh

ARCHS="$(lipo -archs "$APP_DIR/Contents/MacOS/Benri")"
if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
    echo "Expected a universal binary, found: $ARCHS" >&2
    exit 1
fi

rm -f "$ZIP_PATH" "$CHECKSUM_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

cd "$ROOT_DIR/dist"
shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256"

echo "$ZIP_PATH"
echo "$CHECKSUM_PATH"
