#!/usr/bin/env bash
# release.sh — 打里程碑 tag + 发布 GitHub release（阶段成果归档）
# 用法: ./release.sh v0.2.0 ["release 说明"]
# 约定: 语义化版本 vX.Y.Z；每个里程碑一个 tag + 一条 release，notes 写「本阶段成果 + 下阶段计划」。
set -euo pipefail
VER="${1:-}"
[[ -z "$VER" ]] && { echo "用法: $0 vX.Y.Z [说明]"; exit 1; }
NOTES="${2:-$VER 阶段成果}"

command -v gh >/dev/null 2>&1 || { echo "❌ 需要 gh CLI（brew install gh && gh auth login）"; exit 2; }

git tag -a "$VER" -m "$NOTES"
git push origin "$VER"
gh release create "$VER" --title "$VER" --notes "$NOTES"
echo "✅ 已发布里程碑 $VER"
