#!/usr/bin/env bash
# reminders2obsidian.sh — 把 Apple 提醒事项导出为 Markdown 写入 vault
# 用法: ./reminders2obsidian.sh [列表名] [--all]
#   默认写当日 Daily 笔记的「## 提醒」段；可用 OUT 指定文件
# 依赖: osascript（系统自带）；首次运行需在「系统设置→隐私与安全性→自动化」允许终端控制提醒事项
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
VAULT="${VAULT_DIR:-$ROOT/vault}"
OUT="${OUT:-$VAULT/Daily/$(date +%F).md}"
mkdir -p "$(dirname "$OUT")"

MD="$(osascript "$HERE/reminders2obsidian.scpt" "$@" 2>&1)"
# 若目标文件已有「## 提醒」段则替换，否则追加
if grep -q '^## 提醒' "$OUT" 2>/dev/null; then
  python3 - "$OUT" "$MD" <<'PY'
import sys, re
out, md = sys.argv[1], sys.argv[2]
s = open(out, encoding='utf-8').read()
s = re.sub(r'## 提醒.*?(\n## |\Z)', '## 提醒\n\n' + md + r'\1', s, flags=re.S)
open(out, 'w', encoding='utf-8').write(s)
PY
else
  { echo; echo "## 提醒"; echo; echo "$MD"; } >> "$OUT"
fi
echo "提醒已写入 → $OUT"
