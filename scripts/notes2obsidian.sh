#!/usr/bin/env bash
# notes2obsidian.sh — 用 storizzi/notes-exporter 把 Apple Notes 单向导出为 Markdown 并汇入 vault
# 用法: ./notes2obsidian.sh [输出目录]
#   默认导出到 vault/Inbox/notes-export/
# 依赖: ~/tools/notes-exporter（已克隆并建好 .venv）
#   项目: https://github.com/storizzi/notes-exporter
# 注意: 需 Apple「备忘录」App 运行中；首次运行需授予「自动化」权限（系统设置→隐私与安全性→自动化）。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
VAULT="${VAULT_DIR:-$ROOT/vault}"
OUT="${1:-$VAULT/Inbox/notes-export}"
TOOL_DIR="${NOTES_EXPORTER_DIR:-$HOME/tools/notes-exporter}"
mkdir -p "$OUT"

if [[ ! -f "$TOOL_DIR/exportnotes.zsh" ]]; then
  echo "❌ 未找到 notes-exporter，请先安装："
  echo "   git clone https://github.com/storizzi/notes-exporter.git $TOOL_DIR"
  echo "   cd $TOOL_DIR && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
  exit 2
fi

# 若无 venv 则自动创建
if [[ ! -d "$TOOL_DIR/.venv" ]]; then
  echo "创建 venv ..."
  python3 -m venv "$TOOL_DIR/.venv"
  "$TOOL_DIR/.venv/bin/pip" install -q -r "$TOOL_DIR/requirements.txt"
fi

echo "开始导出 Apple Notes → $OUT（请确保备忘录 App 已打开）..."
"$TOOL_DIR/exportnotes.zsh" -m -v "$TOOL_DIR/.venv" -r "$OUT" "$@"
echo "✅ 导出完成。建议在 Obsidian 中用 Templater/Dataview 处理后归档。"

# 附注：v1.3.0 起支持回写双向同步（--sync/--sync-only），见 REFERENCE.md
