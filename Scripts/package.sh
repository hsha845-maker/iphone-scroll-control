#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$REPO_ROOT/build/iPhone Scroll Control.app"
DIST_DIR="$REPO_ROOT/dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO_ROOT/App/Info.plist")"
DMG_PATH="$DIST_DIR/iPhone-Scroll-Control-$VERSION-macOS.dmg"
STAGE_DIR="$(mktemp -d /tmp/iphone-scroll-control-package.XXXXXX)"

"$SCRIPT_DIR/build.sh"
mkdir -p "$DIST_DIR"

/usr/bin/ditto "$APP_PATH" "$STAGE_DIR/iPhone Scroll Control.app"
/usr/bin/ditto "$REPO_ROOT/Installer/安装.command" "$STAGE_DIR/安装.command"
/usr/bin/ditto "$REPO_ROOT/Installer/重新启动.command" "$STAGE_DIR/重新启动.command"
/usr/bin/ditto "$REPO_ROOT/Installer/local.hongxin.iPhoneScrollControl.plist" \
    "$STAGE_DIR/local.hongxin.iPhoneScrollControl.plist"
/usr/bin/ditto "$REPO_ROOT/Docs/安装与使用说明.txt" "$STAGE_DIR/安装与使用说明.txt"

if [[ -f "$REPO_ROOT/Docs/iPhone-Scroll-Control-$VERSION-更新说明.txt" ]]; then
    /usr/bin/ditto "$REPO_ROOT/Docs/iPhone-Scroll-Control-$VERSION-更新说明.txt" \
        "$STAGE_DIR/iPhone-Scroll-Control-$VERSION-更新说明.txt"
fi

chmod +x "$STAGE_DIR/安装.command" "$STAGE_DIR/重新启动.command"
hdiutil create \
    -volname "iPhone Scroll Control $VERSION" \
    -srcfolder "$STAGE_DIR" \
    -ov -format UDZO "$DMG_PATH" >/dev/null
hdiutil verify "$DMG_PATH" >/dev/null

echo "安装包完成：$DMG_PATH"
shasum -a 256 "$DMG_PATH"
