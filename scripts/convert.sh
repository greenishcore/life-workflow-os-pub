#!/usr/bin/env bash
# convert.sh — 格式互转固化 pipeline：任意输入 → Markdown(中间态，缓存) → 目标格式
# 用法:
#   ./convert.sh 输入文件 [-o 输出文件] [--to pdf|docx|html|md]
#   ./convert.sh 输入.pdf --to md          # 只到中间态 Markdown
#   ./convert.sh 输入.docx --to pdf -o out/报告.pdf
#
# 缓存策略: 以 sha256(输入) + 转换器版本 为键，命中直接复用 .cache/，省重复 OCR/LLM 算力。
set -euo pipefail

# ---------- 路径与目录 ----------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
RAW_DIR="${CONVERT_RAW_DIR:-$ROOT/vault/Attachments/_raw}"
MD_DIR="${CONVERT_MD_DIR:-$ROOT/vault/Attachments/_md}"
OUT_DIR="${CONVERT_OUT_DIR:-$ROOT/vault/Attachments/_out}"
CACHE_DIR="${CONVERT_CACHE_DIR:-$ROOT/.cache}"
mkdir -p "$RAW_DIR" "$MD_DIR" "$OUT_DIR" "$CACHE_DIR"

# ---------- 依赖探测 ----------
have() { command -v "$1" >/dev/null 2>&1; }
chrome_bin() {
  for p in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
           "/Applications/Chromium.app/Contents/MacOS/Chromium" \
           "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"; do
    [[ -x "$p" ]] && { echo "$p"; return 0; }
  done
  return 1
}
to_md_tool=""
if have markitdown; then to_md_tool="markitdown";
elif have pandoc; then to_md_tool="pandoc";
fi

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# ---------- 参数解析 ----------
SRC=""; OUT=""; TO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--out) OUT="$2"; shift 2;;
    --to) TO="$2"; shift 2;;
    -h|--help) usage 0;;
    -*) echo "未知参数: $1"; usage 1;;
    *) SRC="$1"; shift;;
  esac
done
[[ -z "$SRC" ]] && { echo "缺少输入文件"; usage 1; }
[[ -f "$SRC" ]] || { echo "文件不存在: $SRC"; exit 1; }

# 目标格式默认由 -o 扩展名推断，否则 pdf
if [[ -z "$TO" ]]; then
  if [[ -n "$OUT" ]]; then TO="${OUT##*.}"; else TO="pdf"; fi
fi

SRC_ABS="$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")"
NAME="$(basename "$SRC_ABS")"; STEM="${NAME%.*}"
[[ "$NAME" != "$SRC" ]] && cp "$SRC" "$RAW_DIR/$NAME"

# ---------- 转换器版本 ----------
conv_ver=""
if [[ "$to_md_tool" == "markitdown" ]]; then conv_ver="markitdown-$(markitdown --version 2>/dev/null | head -1 || echo 0)";
elif [[ "$to_md_tool" == "pandoc" ]]; then conv_ver="pandoc-$(pandoc --version | head -1)";
else conv_ver="none"; fi

# ---------- 第 1 步: 任意 → Markdown（缓存） ----------
ext_lower="${NAME##*.}"
MD_FILE="$MD_DIR/$STEM.md"

if [[ "$ext_lower" == "md" || "$ext_lower" == "markdown" ]]; then
  echo "[is-md] 输入已是 Markdown，跳过转换"
  MD_FILE="$SRC_ABS"
else
  KEY="$(shasum -a 256 "$SRC_ABS" | cut -d' ' -f1)-${conv_ver}"
  CACHE_FILE="$CACHE_DIR/$KEY.md"
  if [[ -s "$CACHE_FILE" ]]; then
    echo "[cache-hit] $NAME"
    cp "$CACHE_FILE" "$MD_FILE"
  else
    TMP="$(mktemp "$CACHE_DIR/.tmp.XXXXXX")"
    case "$to_md_tool" in
      markitdown) echo "[to-md] markitdown $NAME"; markitdown "$SRC_ABS" > "$TMP";;
      pandoc)
        echo "[to-md] pandoc ($ext_lower) $NAME"
        pandoc "$SRC_ABS" -f "$ext_lower" -t gfm --extract-media="$MD_DIR/media" -o "$TMP";;
      *) rm -f "$TMP"; echo "❌ 需要 markitdown 或 pandoc（brew install markitdown pandoc）"; exit 2;;
    esac
    if [[ -s "$TMP" ]]; then
      mv "$TMP" "$CACHE_FILE"
      cp "$CACHE_FILE" "$MD_FILE"
    else
      rm -f "$TMP"
      echo "❌ 转换失败或结果为空: $NAME"; exit 3
    fi
  fi
fi
echo "  → 中间态: $MD_FILE"

# ---------- 第 2 步: Markdown → 目标格式 ----------
if [[ "$TO" == "md" ]]; then
  OUT="${OUT:-$MD_FILE}"
  if [[ "$OUT" != "$MD_FILE" ]]; then cp "$MD_FILE" "$OUT"; fi
  echo "[done] $OUT"
  exit 0
fi
OUT="${OUT:-$OUT_DIR/$STEM.$TO}"

case "$TO" in
  pdf)
    have pandoc || { echo "❌ 生成 PDF 需要 pandoc"; exit 2; }
    if have xelatex; then
      echo "[to-pdf] pandoc+xelatex"
      pandoc "$MD_FILE" -o "$OUT" --pdf-engine=xelatex \
        -V CJKmainfont="PingFang SC" -V geometry:margin=2cm
    elif CHROME="$(chrome_bin 2>/dev/null)"; then
      echo "[to-pdf] Chrome headless"
      TMP_HTML="${OUT%.pdf}.tmp.html"
      pandoc "$MD_FILE" -f gfm -t html --standalone -o "$TMP_HTML"
      "$CHROME" --headless=new --disable-gpu --no-pdf-header-footer \
        --print-to-pdf="$OUT" "file://$TMP_HTML" 2>/dev/null
      rm -f "$TMP_HTML"
    else
      echo "❌ 生成 PDF 需要 xelatex（brew install --cask basictex）或 Chrome"; exit 2
    fi;;
  docx)
    have pandoc || { echo "❌ 生成 docx 需要 pandoc"; exit 2; }
    pandoc "$MD_FILE" -o "$OUT" -f gfm -t docx;;
  html)
    have pandoc || { echo "❌ 生成 html 需要 pandoc"; exit 2; }
    pandoc "$MD_FILE" -o "$OUT" -f gfm -t html --standalone;;
  *) echo "❌ 不支持的目标格式: $TO（支持 md/pdf/docx/html）"; exit 1;;
esac
echo "[done] $OUT"
