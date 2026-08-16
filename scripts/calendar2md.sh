#!/usr/bin/env bash
# calendar2md.sh — 把 Apple 日历未来 N 天事件写入 vault 每日/周视图
# 用法: ./calendar2md.sh [日历名] [天数]
# 依赖: osascript（系统自带）
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
VAULT="${VAULT_DIR:-$ROOT/vault}"
OUT="${OUT:-$VAULT/Daily/$(date +%F).md}"
mkdir -p "$(dirname "$OUT")"

MD="$(osascript "$HERE/calendar2md.scpt" "$@" 2>&1)"
if grep -q '^## 日程' "$OUT" 2>/dev/null; then
  python3 - "$OUT" "$MD" <<'PY'
import sys, re
out, md = sys.argv[1], sys.argv[2]
s = open(out, encoding='utf-8').read()
s = re.sub(r'## 日程.*?(\n## |\Z)', '## 日程\n\n' + md + r'\1', s, flags=re.S)
open(out, 'w', encoding='utf-8').write(s)
PY
else
  { echo; echo "## 日程"; echo; echo "$MD"; } >> "$OUT"
fi
echo "日程已写入 → $OUT"
