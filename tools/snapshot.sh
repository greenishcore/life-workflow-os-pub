#!/usr/bin/env bash
# snapshot.sh — 把 macOS 应用的每一页离屏渲染成 PNG，并指出哪几页与基线不同。
#
# 这是界面设计交接后的**反馈回路**：改完布局跑一次，就知道动了哪些页面。
#
#   bash tools/snapshot.sh                 # 渲染到 .snapshots/current/
#   bash tools/snapshot.sh --baseline      # 把当前结果存为基线
#   bash tools/snapshot.sh --compare       # 渲染并与基线比对，列出有差异的页面
#
# 比对刻意只做**逐字节**判断，不算像素差百分比：
#   1. 目的是告诉你「该看哪几张图」，看图这件事你自己做得比任何相似度指标都准；
#   2. 逐字节比对不需要任何图像库，仓库「零外部依赖、离线可用」的原则不用破例。
# 顺带做一个体积下限检查——整页渲染失败会得到一张几乎全空的图，
# 它压缩后极小，用体积就能抓到，同样不需要解码。
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO/apple/LifeOSApp"
DD="${LIFEOS_DERIVED_DATA:-$REPO/.snapshots/DerivedData}"
OUT_ROOT="$REPO/.snapshots"
FIXTURE="$REPO/.snap"
CURRENT="$OUT_ROOT/current"
BASELINE="$OUT_ROOT/baseline"
MIN_BYTES=20000   # 低于此值几乎可以断定是空白页

mode="render"
case "${1:-}" in
  --baseline) mode="baseline" ;;
  --compare)  mode="compare" ;;
  "")         ;;
  *) echo "未知参数：$1" >&2; exit 2 ;;
esac

# ---------- 1. 夹具 ----------
# 快照要的是「每一页都有内容」，空 vault 截出来的图看不出任何布局问题。
# 夹具用仓库自带的 seed/ 重建，因此任何人任何机器上跑出来的内容都一样。
build_fixture() {
  rm -rf "$FIXTURE"
  mkdir -p "$FIXTURE"/{vault,logs,skills,prompts}
  cp -R "$REPO/seed/vault/." "$FIXTURE/vault/"
  mkdir -p "$FIXTURE/vault/Inbox" "$FIXTURE/vault/Projects"
  cp "$REPO"/seed/examples/Inbox/*.md    "$FIXTURE/vault/Inbox/"
  cp "$REPO"/seed/examples/Projects/*.md "$FIXTURE/vault/Projects/"
  cp "$REPO"/seed/skills/*.md "$FIXTURE/skills/"
  cat > "$FIXTURE/logs/run-log.jsonl" <<'JSONL'
{"t":"2026-01-18T09:12:03Z","action":"convert","objective":"把调研 PDF 转成 Markdown","tool":"markitdown","status":"ok","duration_ms":820,"cache_hit":false,"notes":"12 页，图表保留"}
{"t":"2026-01-18T09:31:44Z","action":"convert","objective":"把调研 PDF 转成 Markdown","tool":"markitdown","status":"ok","duration_ms":11,"cache_hit":true,"notes":"命中缓存"}
{"t":"2026-01-19T14:02:10Z","action":"prompt","objective":"把口语需求改写成五段式提示词","tool":"llm","status":"ok","duration_ms":2400,"cache_hit":false,"notes":""}
{"t":"2026-01-19T16:45:00Z","action":"git","objective":"阶段成果提交并推送","tool":"git","status":"ok","duration_ms":1530,"cache_hit":false,"notes":"3 个文件"}
{"t":"2026-01-20T10:20:31Z","action":"convert","objective":"Markdown 导出 PDF","tool":"pandoc","status":"error","duration_ms":640,"cache_hit":false,"notes":"缺 xelatex，回退 Chrome"}
JSONL
}

# ---------- 2. 构建 ----------
build_app() {
  command -v xcodegen >/dev/null || { echo "❌ 需要 xcodegen（brew install xcodegen）" >&2; exit 1; }
  ( cd "$APP_DIR" && xcodegen generate >/dev/null )
  # 注意取 xcodebuild 自己的退出码：接管道之后 $? 是管道末端命令的，会把失败吞掉
  set -o pipefail
  if ! ( cd "$APP_DIR" && xcodebuild -project LifeOS.xcodeproj -scheme LifeOS-macOS \
          -configuration Debug -derivedDataPath "$DD" -quiet build ) > "$OUT_ROOT/build.log" 2>&1; then
    echo "❌ 构建失败，见 $OUT_ROOT/build.log" >&2
    grep -E 'error:' "$OUT_ROOT/build.log" | head -20 >&2 || true
    exit 1
  fi
}

# ---------- 3. 渲染 ----------
render() {
  local dest="$1"
  rm -rf "$dest"
  local bin="$DD/Build/Products/Debug/Life Workflow OS.app/Contents/MacOS/Life Workflow OS"
  [ -x "$bin" ] || { echo "❌ 找不到可执行文件：$bin" >&2; exit 1; }
  "$bin" --snapshot "$dest" --vault "$FIXTURE/vault" > "$OUT_ROOT/render.log" 2>&1 \
    || { echo "❌ 渲染失败，见 $OUT_ROOT/render.log" >&2; tail -5 "$OUT_ROOT/render.log" >&2; exit 1; }
  grep -E '数据就绪' "$OUT_ROOT/render.log" || true

  local suspicious=0
  for f in "$dest"/*.png; do
    local size; size=$(stat -f%z "$f")
    if [ "$size" -lt "$MIN_BYTES" ]; then
      echo "  ⚠️  $(basename "$f") 只有 $((size/1024))KB，很可能整页渲染成了空白"
      suspicious=$((suspicious+1))
    fi
  done
  echo "  渲染 $(ls "$dest"/*.png | wc -l | tr -d ' ') 张，可疑空白 $suspicious 张"
  [ "$suspicious" -eq 0 ] || return 1
}

mkdir -p "$OUT_ROOT"
build_fixture
build_app

case "$mode" in
  render)
    render "$CURRENT"
    echo "✅ → $CURRENT"
    ;;
  baseline)
    render "$BASELINE"
    echo "✅ 基线已更新 → $BASELINE"
    echo "   基线不入库（18 张约 7MB，每次设计改动都重传会把仓库撑大）"
    ;;
  compare)
    [ -d "$BASELINE" ] || { echo "❌ 还没有基线，先跑 bash tools/snapshot.sh --baseline" >&2; exit 1; }
    render "$CURRENT"
    echo
    echo "── 与基线比对 ──"
    changed=0; same=0
    for f in "$CURRENT"/*.png; do
      n=$(basename "$f")
      if [ ! -f "$BASELINE/$n" ]; then
        echo "  🆕 $n（基线里没有这一页）"; changed=$((changed+1))
      elif cmp -s "$f" "$BASELINE/$n"; then
        same=$((same+1))
      else
        echo "  ⚠️  $n  $BASELINE/$n  →  $f"; changed=$((changed+1))
      fi
    done
    echo
    echo "  未变 $same 张 · 有差异 $changed 张"
    [ "$changed" -eq 0 ] && echo "  ✅ 与基线完全一致" \
      || echo "  ↑ 打开上面这几对图逐一对照。字号/间距类改动通常只影响个别页面；"
    [ "$changed" -eq 0 ] || echo "    如果差异页远多于你改动涉及的页面，多半是动到了 Theme 里的共用组件。"
    ;;
esac
