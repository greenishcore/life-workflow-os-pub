#!/usr/bin/env bash
# snapshot-ios.sh — 在模拟器里截下 iOS 应用每个标签页的明暗两版。
#
#   bash tools/snapshot-ios.sh                 # 截到 .snapshots/ios-current/
#   bash tools/snapshot-ios.sh --baseline      # 存为基线
#   bash tools/snapshot-ios.sh --compare       # 截图并与基线比对
#
# 为什么 iOS 不用 macOS 那套 ImageRenderer 离屏渲染：
# iOS 的页面全是 NavigationStack + List / Form，它们都由 UIKit 支撑，
# ImageRenderer 渲不出来（macOS 端 HSplitView 也是同样的毛病，那边是靠
# isSnapshotting 换成 HStack 绕过的）。给每个页面都做一套快照替身既侵入又失真，
# 而模拟器截的是**真实画面**——List、TabView、图表全都对。
# 代价是需要一台已启动的模拟器，不能完全无头。
#
# 切页靠应用已有的 `--tab` 启动参数：模拟器里注入不了点击，只能靠启动参数选页。
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO/apple/LifeOSApp"
BUNDLE_ID="com.lifeos.workflow"
DD="${LIFEOS_IOS_DERIVED_DATA:-$REPO/.snapshots/DerivedData-iOS}"
OUT_ROOT="$REPO/.snapshots"
CURRENT="$OUT_ROOT/ios-current"
BASELINE="$OUT_ROOT/ios-baseline"
TABS=(today capture ideas dashboard settings)
SETTLE=${LIFEOS_SNAPSHOT_SETTLE:-4}   # 启动后等界面稳定的秒数
MIN_BYTES=40000

mode="render"
case "${1:-}" in
  --baseline) mode="baseline" ;;
  --compare)  mode="compare" ;;
  "")         ;;
  *) echo "未知参数：$1" >&2; exit 2 ;;
esac

# ---------- 找一台已启动的模拟器 ----------
DEV=$(xcrun simctl list devices booted -j 2>/dev/null | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
booted = [d["udid"] for v in devices.values() for d in v if d["state"] == "Booted"]
print(booted[0] if booted else "")
')
if [ -z "$DEV" ]; then
  echo "❌ 没有已启动的模拟器。先开一台，例如：" >&2
  echo "   xcrun simctl boot 'iPhone 17 Pro' && open -a Simulator" >&2
  exit 1
fi
echo "模拟器 $DEV"

# ---------- 构建并安装 ----------
command -v xcodegen >/dev/null || { echo "❌ 需要 xcodegen（brew install xcodegen）" >&2; exit 1; }
( cd "$APP_DIR" && xcodegen generate >/dev/null )
mkdir -p "$OUT_ROOT"
set -o pipefail
if ! ( cd "$APP_DIR" && xcodebuild -project LifeOS.xcodeproj -scheme LifeOS-iOS \
        -configuration Debug -destination "id=$DEV" -derivedDataPath "$DD" -quiet build ) \
        > "$OUT_ROOT/build-ios.log" 2>&1; then
  echo "❌ 构建失败，见 $OUT_ROOT/build-ios.log" >&2
  grep -E 'error:' "$OUT_ROOT/build-ios.log" | head -20 >&2 || true
  exit 1
fi
APP=$(find "$DD/Build/Products" -maxdepth 3 -name '*.app' | head -1)
[ -n "$APP" ] || { echo "❌ 找不到 .app 产物" >&2; exit 1; }
xcrun simctl install "$DEV" "$APP" >/dev/null

# ---------- 把夹具塞进 App 容器 ----------
# 不这么做，截出来的是这台模拟器上残留的旧数据，不同机器结果不一致。
CONTAINER=$(xcrun simctl get_app_container "$DEV" "$BUNDLE_ID" data)
VAULT="$CONTAINER/Documents/LifeOSVault"
rm -rf "$VAULT"
mkdir -p "$VAULT/Inbox" "$VAULT/Projects"
cp -R "$REPO/seed/vault/." "$VAULT/"
cp "$REPO"/seed/examples/Inbox/*.md    "$VAULT/Inbox/"
cp "$REPO"/seed/examples/Projects/*.md "$VAULT/Projects/"
echo "夹具就绪：$(find "$VAULT" -name '*.md' | wc -l | tr -d ' ') 个文件"

# ---------- 逐页截图 ----------
render() {
  local dest="$1"
  rm -rf "$dest"; mkdir -p "$dest"
  for appearance in light dark; do
    xcrun simctl ui "$DEV" appearance "$appearance" >/dev/null 2>&1 || true
    for tab in "${TABS[@]}"; do
      xcrun simctl terminate "$DEV" "$BUNDLE_ID" >/dev/null 2>&1 || true
      xcrun simctl launch "$DEV" "$BUNDLE_ID" --tab "$tab" >/dev/null
      sleep "$SETTLE"
      xcrun simctl io "$DEV" screenshot "$dest/$tab-$appearance.png" >/dev/null 2>&1
      printf '  ✅ %s-%s.png\n' "$tab" "$appearance"
    done
  done
  xcrun simctl terminate "$DEV" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl ui "$DEV" appearance light >/dev/null 2>&1 || true

  local suspicious=0
  for f in "$dest"/*.png; do
    local size; size=$(stat -f%z "$f")
    if [ "$size" -lt "$MIN_BYTES" ]; then
      echo "  ⚠️  $(basename "$f") 只有 $((size/1024))KB，可能没渲染出来"
      suspicious=$((suspicious+1))
    fi
  done
  echo "  共 $(ls "$dest"/*.png | wc -l | tr -d ' ') 张，可疑 $suspicious 张"
}

case "$mode" in
  render)   render "$CURRENT";  echo "✅ → $CURRENT" ;;
  baseline) render "$BASELINE"; echo "✅ iOS 基线已更新 → $BASELINE" ;;
  compare)
    [ -d "$BASELINE" ] || { echo "❌ 还没有 iOS 基线，先跑 --baseline" >&2; exit 1; }
    render "$CURRENT"
    echo
    echo "── 与基线比对 ──"
    changed=0; same=0
    for f in "$CURRENT"/*.png; do
      n=$(basename "$f")
      if [ ! -f "$BASELINE/$n" ]; then echo "  🆕 $n"; changed=$((changed+1))
      elif cmp -s "$f" "$BASELINE/$n"; then same=$((same+1))
      else echo "  ⚠️  $n"; changed=$((changed+1)); fi
    done
    echo
    echo "  未变 $same 张 · 有差异 $changed 张"
    # 模拟器截的是整块屏幕，状态栏带着时钟——时间一变字节就不同。
    # 所以 iOS 这边「有差异」是常态，图要人（或 agent）自己看，不能只看计数。
    [ "$changed" -eq 0 ] || echo "  注意：状态栏时钟每分钟都在变，逐字节比对必然报差异；这里的清单只用来定位该看哪几张。"
    ;;
esac
