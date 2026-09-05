#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_FILE="$REPO_ROOT/Sources/main.swift"
INFO_PLIST="$REPO_ROOT/App/Info.plist"
BUILD_DIR="$REPO_ROOT/build"
APP_PATH="$BUILD_DIR/iPhone Scroll Control.app"
MACOS_DIR="$APP_PATH/Contents/MacOS"
MODULE_CACHE="${TMPDIR:-/tmp}/iphone-scroll-control-swift-module-cache"

mkdir -p "$BUILD_DIR" "$MACOS_DIR" "$MODULE_CACHE"

xcrun swiftc -module-cache-path "$MODULE_CACHE" -O -target arm64-apple-macosx15.0 \
    "$SOURCE_FILE" -o "$BUILD_DIR/iphone-scroll-control-arm64"
xcrun swiftc -module-cache-path "$MODULE_CACHE" -O -target x86_64-apple-macosx15.0 \
    "$SOURCE_FILE" -o "$BUILD_DIR/iphone-scroll-control-x86_64"

lipo -create \
    "$BUILD_DIR/iphone-scroll-control-arm64" \
    "$BUILD_DIR/iphone-scroll-control-x86_64" \
    -output "$MACOS_DIR/iphone-scroll-control"

/usr/bin/ditto "$INFO_PLIST" "$APP_PATH/Contents/Info.plist"
codesign --force --deep --sign - "$APP_PATH"

echo "构建完成：$APP_PATH"
file "$MACOS_DIR/iphone-scroll-control"
