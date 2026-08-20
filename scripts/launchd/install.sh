#!/usr/bin/env bash
# install.sh — 安装「提醒/日历 → vault」的定时同步任务
#
# 之所以需要这个脚本：launchd 的 plist 不展开 $HOME 之类的变量，路径必须写绝对的。
# 与其让你手改 plist（改错了 launchd 只会静默不跑），不如按你的真实环境生成。
#
#   bash scripts/launchd/install.sh              # 用默认提醒列表
#   bash scripts/launchd/install.sh 我的提醒      # 指定列表名
#
# 卸载：
#   launchctl bootout gui/$(id -u)/com.lifeos.sync
#   rm ~/Library/LaunchAgents/com.lifeos.sync.plist
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REMINDER_LIST="${1:-提醒事项}"

# vault 位置以 lifeos 自己的配置为准，避免「应用读 A、定时任务写 B」
VAULT_DIR="$(cd "$REPO_ROOT" && python3 -c 'from lifeos.config import get_config; print(get_config().vault)' 2>/dev/null || true)"
if [ -z "$VAULT_DIR" ]; then
  VAULT_DIR="$HOME/LifeWorkflowOS/vault"
  echo "⚠️  读不到 lifeos 配置，退回默认 vault：$VAULT_DIR" >&2
fi

TARGET="$HOME/Library/LaunchAgents/com.lifeos.sync.plist"
mkdir -p "$(dirname "$TARGET")"
sed -e "s|__REPO_ROOT__|$REPO_ROOT|g" \
    -e "s|__REMINDER_LIST__|$REMINDER_LIST|g" \
    -e "s|__VAULT_DIR__|$VAULT_DIR|g" \
    "$REPO_ROOT/scripts/launchd/com.lifeos.sync.plist.template" > "$TARGET"

launchctl bootout "gui/$(id -u)/com.lifeos.sync" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$TARGET"
echo "✅ 已安装：$TARGET"
echo "   仓库   $REPO_ROOT"
echo "   vault  $VAULT_DIR"
echo "   列表   $REMINDER_LIST"
echo "   日志   /tmp/com.lifeos.sync.log"
