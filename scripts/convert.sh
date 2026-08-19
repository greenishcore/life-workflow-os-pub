#!/usr/bin/env bash
# convert.sh — 兼容壳：逻辑已统一到 lifeos 包（等价 python3 -m lifeos.cli convert）
# 用法:
#   ./convert.sh 输入文件 [-o 输出文件] [--to pdf|docx|html|md]
# 缓存策略: sha256(输入)+转换器版本 为键，命中直接复用 .cache/
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
exec python3 -m lifeos.cli convert "$@"
