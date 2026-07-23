#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${BENRI_DIST_DIR:-$ROOT_DIR/dist}"
APP_DIR="$DIST_DIR/Benri.app"
LEGACY_BENRI_APP_DIR="$DIST_DIR/benri.app"
LEGACY_VALUET_APP_DIR="$DIST_DIR/valuet.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$ROOT_DIR/.build/Benri.iconset"
ICON_FILE="$ROOT_DIR/.build/Benri.icns"
LOCAL_CODESIGN_IDENTITY="Benri Local Code Signing"
if [[ -z "${CODESIGN_IDENTITY+x}" ]]; then
    if /usr/bin/security find-identity -p codesigning -v \
        | /usr/bin/grep -Fq "\"$LOCAL_CODESIGN_IDENTITY\""; then
        CODESIGN_IDENTITY="$LOCAL_CODESIGN_IDENTITY"
    else
        CODESIGN_IDENTITY="-"
    fi
fi
ARCH_LIST="${BENRI_ARCHS:-$(uname -m)}"
typeset -a ARCHS
typeset -a BINARIES
typeset -a EXTRA_BUILD_FLAGS
ARCHS=(${=ARCH_LIST})
BINARIES=()
EXTRA_BUILD_FLAGS=()

if [[ -n "${SWIFT_BUILD_FLAGS:-}" ]]; then
    EXTRA_BUILD_FLAGS=(${=SWIFT_BUILD_FLAGS})
fi

cd "$ROOT_DIR"
mkdir -p "$DIST_DIR"
touch "$DIST_DIR/.metadata_never_index"

for ARCH in "${ARCHS[@]}"; do
    SCRATCH_PATH="$ROOT_DIR/.build/release-$ARCH"
    TRIPLE="$ARCH-apple-macosx13.0"
    swift build \
        "${EXTRA_BUILD_FLAGS[@]}" \
        -c release \
        --product Benri \
        --triple "$TRIPLE" \
        --scratch-path "$SCRATCH_PATH"
    BIN_DIR="$(swift build \
        "${EXTRA_BUILD_FLAGS[@]}" \
        -c release \
        --triple "$TRIPLE" \
        --scratch-path "$SCRATCH_PATH" \
        --show-bin-path)"
    BINARIES+=("$BIN_DIR/Benri")
done

rm -rf \
    "$APP_DIR" \
    "$LEGACY_BENRI_APP_DIR" \
    "$LEGACY_VALUET_APP_DIR" \
    "$ICONSET_DIR" \
    "$ICON_FILE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

if (( ${#BINARIES[@]} == 1 )); then
    cp "${BINARIES[1]}" "$MACOS_DIR/Benri"
else
    lipo -create "${BINARIES[@]}" -output "$MACOS_DIR/Benri"
fi
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

swift "$ROOT_DIR/Scripts/generate-icon.swift" \
    "$ICONSET_DIR" \
    "$ROOT_DIR/Resources/benri-icon-source.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
cp "$ICON_FILE" "$RESOURCES_DIR/Benri.icns"

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$APP_DIR"
elif [[ "$CODESIGN_IDENTITY" == "$LOCAL_CODESIGN_IDENTITY" ]]; then
    codesign \
        --force \
        --deep \
        --options runtime \
        --sign "$CODESIGN_IDENTITY" \
        "$APP_DIR"
else
    codesign \
        --force \
        --deep \
        --options runtime \
        --timestamp \
        --sign "$CODESIGN_IDENTITY" \
        "$APP_DIR"
fi
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "$APP_DIR"
