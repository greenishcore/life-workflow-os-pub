#!/usr/bin/env bash
# release.sh — 兼容壳：等价 python3 -m lifeos.cli release
# 用法: ./release.sh v0.2.0 ["release 说明"]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ -z "${1:-}" ]] && { echo "用法: $0 vX.Y.Z [说明]"; exit 1; }
exec python3 -m lifeos.cli release "$@"
