#!/usr/bin/env bash
# sync.sh — 一键 git 提交 + 推送（供 obsidian-git 之外的定时/手动同步用）
# 用法: ./sync.sh [额外 commit 参数]
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || { echo "不在 git 仓库内"; exit 1; })"

git pull --rebase --autostash -q 2>/dev/null || true
git add -A
if git diff --cached --quiet; then
  echo "无变更，跳过"
  exit 0
fi
git commit -q -m "auto: $(date '+%Y-%m-%d %H:%M') 工作流同步" "$@"
git push -q
echo "✅ 已提交并推送"
