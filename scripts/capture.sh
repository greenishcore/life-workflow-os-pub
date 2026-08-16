#!/usr/bin/env bash
# capture.sh — 快速捕获：把一段文字追加到 vault/Inbox/（供命令行/快捷指令/剪贴板）
# 用法:
#   ./capture.sh "突然想到的点子"
#   echo "某段内容" | ./capture.sh        # 从标准输入
#   ./capture.sh                          # 无参数时读剪贴板
# 环境变量:
#   VAULT_DIR      vault 根目录（默认 $ROOT/vault）
#   CAPTURE_FILE   落点文件（默认 Inbox/当天日期.md）
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
VAULT="${VAULT_DIR:-$ROOT/vault}"
TARGET="${CAPTURE_FILE:-$VAULT/Inbox/$(date +%F).md}"
mkdir -p "$(dirname "$TARGET")"

text=""
if [[ $# -gt 0 ]]; then
  text="$*"
elif [[ ! -t 0 ]]; then
  text="$(cat)"
else
  text="$(pbpaste 2>/dev/null || true)"
fi

[[ -z "${text// }" ]] && { echo "无输入内容（参数/stdin/剪贴板均为空）"; exit 1; }

{ echo; echo "- [ ] $(date +%H:%M) ${text}"; } >> "$TARGET"
echo "已捕获 → $TARGET"
