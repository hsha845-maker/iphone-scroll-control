#!/bin/zsh
set -euo pipefail

LABEL="local.hongxin.iPhoneScrollControl"
USER_ID="$(id -u)"
AGENT_FILE="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ ! -f "$AGENT_FILE" ]]; then
  echo "尚未安装。请先运行“安装.command”。"
else
  launchctl bootout "gui/$USER_ID/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$USER_ID" "$AGENT_FILE"
  launchctl kickstart -k "gui/$USER_ID/$LABEL"
  echo "iPhone Scroll Control 已重新启动。"
fi

read -k 1 "?按任意键关闭窗口…"
