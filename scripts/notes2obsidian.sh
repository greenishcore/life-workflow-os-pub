#!/usr/bin/env bash
# notes2obsidian.sh — 用 notes-exporter 把 Apple Notes 单向导出为 Markdown 并汇入 vault
# 用法: ./notes2obsidian.sh [输出目录]
#   默认导出到 vault/Inbox/notes-export/
# 依赖: notes-exporter（pipx install notes-exporter 或 pip install notes-exporter）
#   项目: https://github.com/storizzi/notes-exporter
# 说明: Apple Notes 底层为私有格式，无可靠双向同步，此处为单向导出（推荐架构）。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
VAULT="${VAULT_DIR:-$ROOT/vault}"
OUT="${1:-$VAULT/Inbox/notes-export}"
mkdir -p "$OUT"

if ! command -v notes-exporter >/dev/null 2>&1 && ! python3 -c "import notes_exporter" 2>/dev/null; then
  echo "❌ 未安装 notes-exporter，请先执行: pipx install notes-exporter"
  echo "   或参考 https://github.com/storizzi/notes-exporter"
  exit 2
fi

echo "开始导出 Apple Notes → $OUT ..."
if command -v notes-exporter >/dev/null 2>&1; then
  notes-exporter --target-dir "$OUT" "$@"
else
  python3 -m notes_exporter "$OUT" "$@"
fi
echo "✅ 导出完成。建议在 Obsidian 中用 Templater/Dataview 处理后归档。"
