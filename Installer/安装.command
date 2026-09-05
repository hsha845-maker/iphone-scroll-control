#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$SCRIPT_DIR/iPhone Scroll Control.app"
TARGET_DIR="$HOME/Applications"
TARGET_APP="$TARGET_DIR/iPhone Scroll Control.app"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT_FILE="$AGENT_DIR/local.hongxin.iPhoneScrollControl.plist"
LABEL="local.hongxin.iPhoneScrollControl"
USER_ID="$(id -u)"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "找不到安装文件：$SOURCE_APP"
  read -k 1 "?按任意键退出…"
  exit 1
fi

mkdir -p "$TARGET_DIR" "$AGENT_DIR" "$HOME/Library/Logs"
launchctl bootout "gui/$USER_ID/$LABEL" 2>/dev/null || true

if [[ -e "$TARGET_APP" ]]; then
  BACKUP_APP="$TARGET_DIR/iPhone Scroll Control.previous-$(date +%Y%m%d-%H%M%S).app"
  mv "$TARGET_APP" "$BACKUP_APP"
  echo "旧版本已备份到：$BACKUP_APP"
fi

/usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"
/bin/cp "$SCRIPT_DIR/local.hongxin.iPhoneScrollControl.plist" "$AGENT_FILE"

/usr/libexec/PlistBuddy -c "Set :ProgramArguments:2 $TARGET_APP" "$AGENT_FILE"
/usr/libexec/PlistBuddy -c "Set :StandardOutPath $HOME/Library/Logs/iPhoneScrollControl.log" "$AGENT_FILE"
/usr/libexec/PlistBuddy -c "Set :StandardErrorPath $HOME/Library/Logs/iPhoneScrollControl.error.log" "$AGENT_FILE"

launchctl bootstrap "gui/$USER_ID" "$AGENT_FILE"
launchctl kickstart -k "gui/$USER_ID/$LABEL" || true

echo
echo "安装完成：$TARGET_APP"
echo "已设置为登录后自动运行。"
echo
echo "接下来请按照《安装与使用说明》开启："
echo "1. 辅助功能"
echo "2. 输入监控"
echo "3. 屏幕与系统音频录制"
echo
read -k 1 "?按任意键关闭窗口…"
