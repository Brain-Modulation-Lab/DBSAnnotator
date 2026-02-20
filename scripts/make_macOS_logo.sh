#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ICON_DIR="$SCRIPT_DIR/../icons"
ICONSET="$ICON_DIR/logobml.iconset"
SRC_ICON="$ICON_DIR/logobml.png"

mkdir -p "$ICONSET"

sips -z 16 16     "$SRC_ICON" --out "$ICONSET/icon_16x16.png"
sips -z 32 32     "$SRC_ICON" --out "$ICONSET/icon_16x16@2x.png"
sips -z 32 32     "$SRC_ICON" --out "$ICONSET/icon_32x32.png"
sips -z 64 64     "$SRC_ICON" --out "$ICONSET/icon_32x32@2x.png"
sips -z 128 128   "$SRC_ICON" --out "$ICONSET/icon_128x128.png"
sips -z 256 256   "$SRC_ICON" --out "$ICONSET/icon_128x128@2x.png"
sips -z 256 256   "$SRC_ICON" --out "$ICONSET/icon_256x256.png"
sips -z 512 512   "$SRC_ICON" --out "$ICONSET/icon_256x256@2x.png"
sips -z 512 512   "$SRC_ICON" --out "$ICONSET/icon_512x512.png"

cp "$SRC_ICON" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$ICON_DIR/logobml.icns"