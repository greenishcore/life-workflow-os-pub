#!/usr/bin/env bash
# sync.sh — 兼容壳：等价 python3 -m lifeos.cli sync
# 用法: ./sync.sh ["commit 说明"]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
exec python3 -m lifeos.cli sync ${1:+-m "$1"}
