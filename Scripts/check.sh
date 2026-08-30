#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

xcrun swiftc -typecheck "$REPO_ROOT/Sources/main.swift"
plutil -lint "$REPO_ROOT/App/Info.plist"
plutil -lint "$REPO_ROOT/Installer/local.hongxin.iPhoneScrollControl.plist"
zsh -n "$REPO_ROOT/Installer/安装.command"
zsh -n "$REPO_ROOT/Installer/重新启动.command"
zsh -n "$REPO_ROOT/Scripts/build.sh"
zsh -n "$REPO_ROOT/Scripts/package.sh"

echo "检查通过。"
