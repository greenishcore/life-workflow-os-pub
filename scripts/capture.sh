#!/usr/bin/env bash
# capture.sh — 兼容壳：逻辑已统一到 lifeos 包（等价 python3 -m lifeos.cli capture）
# 用法:
#   ./capture.sh "突然想到的点子"
#   echo "某段内容" | ./capture.sh        # 从标准输入
#   ./capture.sh                          # 无参数时读剪贴板
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
exec python3 -m lifeos.cli capture "$@"
