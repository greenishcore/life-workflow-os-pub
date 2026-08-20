#!/usr/bin/env bash
# snapshot-sim.sh — 在模拟器里截下 iOS / watchOS 应用每一屏。
#
#   bash tools/snapshot-sim.sh ios                 # 截到 .snapshots/ios-current/
#   bash tools/snapshot-sim.sh ios --baseline      # 存为基线
#   bash tools/snapshot-sim.sh watch --compare     # 截图并与基线比对
#
# 为什么这两端不用 macOS 那套 ImageRenderer 离屏渲染：
# iOS 与 watchOS 的页面全是 NavigationStack + List / Form，都由 UIKit 支撑，
# ImageRenderer 渲不出来（macOS 端的 HSplitView 也是同样的毛病，那边靠
# isSnapshotting 换成 HStack 绕过）。给每个页面做快照替身既侵入又失真，
# 而模拟器截的是**真实画面**。代价是需要一台已启动的模拟器，不能完全无头。
#
# 切屏靠应用已有的启动参数（iOS 是 --tab、watchOS 是 --screen）：
# 模拟器里注入不了点击，只能靠启动参数直接落到要拍的那一屏。
#
# 两端合在一份脚本里，是因为流程九成相同；分两份必然漂移。
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO/apple/LifeOSApp"
OUT_ROOT="$REPO/.snapshots"
SETTLE=${LIFEOS_SNAPSHOT_SETTLE:-4}

platform="${1:-}"
mode="${2:-render}"
case "$platform" in
  ios)
    SCHEME=LifeOS-iOS
    BUNDLE_ID=com.lifeos.workflow
    RUNTIME_MATCH=iOS
    SCREEN_ARG=--tab
    SCREENS=(today capture ideas dashboard settings)
    # iOS 明暗两套都要看
    APPEARANCES=(light dark)
    PREFIX=ios
    MIN_INK=0.01      # 实测：空白 0.0000，正常最简页 0.0526
    SKIP_TOP=0.08     # 跳过状态栏（时钟每分钟变）
    ;;
  watch)
    SCHEME=LifeOS-watchOS
    BUNDLE_ID=com.lifeos.workflow.watchkitapp
    RUNTIME_MATCH=watchOS
    SCREEN_ARG=--screen
    SCREENS=(overview ideas detail)
    # watchOS **没有浅色模式**（simctl ui appearance light 返回 Operation not supported），
    # 表盘永远是黑底，所以只截暗色一套。
    APPEARANCES=(dark)
    PREFIX=watch
    MIN_INK=0.05      # 表盘是黑底浅字，正常页在 0.6 以上
    SKIP_TOP=0.15
    ;;
  *)
    echo "用法：bash tools/snapshot-sim.sh <ios|watch> [--baseline|--compare]" >&2
    exit 2
    ;;
esac
case "$mode" in
  render|--baseline|--compare) ;;
  *) echo "未知参数：$mode" >&2; exit 2 ;;
esac
CURRENT="$OUT_ROOT/$PREFIX-current"
BASELINE="$OUT_ROOT/$PREFIX-baseline"

# ---------- 找一台已启动的对应平台模拟器 ----------
DEV=$(xcrun simctl list devices booted -j 2>/dev/null | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
for runtime, items in devices.items():
    if '$RUNTIME_MATCH' not in runtime:
        continue
    for d in items:
        if d['state'] == 'Booted':
            print(d['udid']); sys.exit()
")
if [ -z "$DEV" ]; then
  echo "❌ 没有已启动的 $RUNTIME_MATCH 模拟器。先开一台：" >&2
  if [ "$platform" = "ios" ]; then
    echo "   xcrun simctl boot 'iPhone 17 Pro' && open -a Simulator" >&2
  else
    echo "   xcrun simctl boot 'Apple Watch Series 11 (46mm)' && open -a Simulator" >&2
  fi
  exit 1
fi
echo "$RUNTIME_MATCH 模拟器 $DEV"

# ---------- 构建并安装 ----------
command -v xcodegen >/dev/null || { echo "❌ 需要 xcodegen（brew install xcodegen）" >&2; exit 1; }
( cd "$APP_DIR" && xcodegen generate >/dev/null )
mkdir -p "$OUT_ROOT"
DD="$OUT_ROOT/DerivedData-$PREFIX"
set -o pipefail
if ! ( cd "$APP_DIR" && xcodebuild -project LifeOS.xcodeproj -scheme "$SCHEME" \
        -configuration Debug -destination "id=$DEV" -derivedDataPath "$DD" -quiet build ) \
        > "$OUT_ROOT/build-$PREFIX.log" 2>&1; then
  echo "❌ 构建失败，见 $OUT_ROOT/build-$PREFIX.log" >&2
  grep -E 'error:' "$OUT_ROOT/build-$PREFIX.log" | head -20 >&2 || true
  exit 1
fi
# 产物路径从 xcodebuild 问，不靠 find 猜：构建目录里同时躺着多个 .app
# （手表是伴侣应用，iOS 产物里嵌着它），find 撞上哪个是随机的。
#
# 必须**按 target 段落取**，不能各取最后一条：手表 scheme 会连带拉进 iOS 宿主，
# showBuildSettings 因此返回两个 target 的设置，混着取会把 iOS 的路径
# 配上手表的安装目标（第一次就这么装错了）。
APP=$( cd "$APP_DIR" && xcodebuild -project LifeOS.xcodeproj -scheme "$SCHEME" \
        -configuration Debug -destination "id=$DEV" -derivedDataPath "$DD" \
        -showBuildSettings 2>/dev/null | awk -F' = ' -v want="$SCHEME" '
          /^Build settings for action build and target / {
              t = $0; sub(/.*target /, "", t); sub(/:.*/, "", t)
              cur = (t == want)
              next
          }
          cur && /  TARGET_BUILD_DIR = /  { dir = $2 }
          cur && /  FULL_PRODUCT_NAME = / { name = $2 }
          END { if (dir && name) print dir "/" name }' )
[ -n "$APP" ] && [ -d "$APP" ] || { echo "❌ 找不到 $SCHEME 的 .app 产物（拿到的是「$APP」）" >&2; exit 1; }
echo "产物 $(basename "$APP")"
# ---------- 每张截图前：全新安装 + 塞夹具 ----------
# **必须卸载重装，不能只 terminate。** SwiftUI 会恢复上次的滚动位置，
# 只终止进程再启动，List 会停在上次翻到的地方——手表端就因此出过一次
# 「基线是滚到中途截的」，比对报了 75% 假差异。
# 卸载会连容器一起清掉，所以夹具要跟着重铺；铺 9 个文件是瞬间的事。
fresh_install() {
  xcrun simctl uninstall "$DEV" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$DEV" "$APP" >/dev/null
  local container vault
  container=$(xcrun simctl get_app_container "$DEV" "$BUNDLE_ID" data)
  vault="$container/Documents/LifeOSVault"
  rm -rf "$vault"
  mkdir -p "$vault/Inbox" "$vault/Projects"
  cp -R "$REPO/seed/vault/." "$vault/"
  cp "$REPO"/seed/examples/Inbox/*.md    "$vault/Inbox/"
  cp "$REPO"/seed/examples/Projects/*.md "$vault/Projects/"
}
fresh_install
echo "夹具就绪：$(find "$(xcrun simctl get_app_container "$DEV" "$BUNDLE_ID" data)/Documents/LifeOSVault" -name '*.md' | wc -l | tr -d ' ') 个文件"

render() {
  local dest="$1"
  rm -rf "$dest"; mkdir -p "$dest"
  for appearance in "${APPEARANCES[@]}"; do
    xcrun simctl ui "$DEV" appearance "$appearance" >/dev/null 2>&1 || true
    for screen in "${SCREENS[@]}"; do
      fresh_install     # 冷启动，避免上一张的滚动位置带进来
      xcrun simctl launch "$DEV" "$BUNDLE_ID" "$SCREEN_ARG" "$screen" >/dev/null
      sleep "$SETTLE"
      xcrun simctl io "$DEV" screenshot "$dest/$screen-$appearance.png" >/dev/null 2>&1
      printf '  ✅ %s-%s.png\n' "$screen" "$appearance"
    done
  done
  xcrun simctl terminate "$DEV" "$BUNDLE_ID" >/dev/null 2>&1 || true
  [ "$platform" = "ios" ] && { xcrun simctl ui "$DEV" appearance light >/dev/null 2>&1 || true; }

  # 用真实像素判断有没有渲染出来。**别用文件体积**——实测一张完全空白的
  # iOS 截图有 74KB（状态栏、圆角、设备边框就压出这么多），比任何合理的
  # 体积阈值都大，那种守卫等于不存在，而空白图一旦成了基线，后面全废。
  local suspicious=0
  for f in "$dest"/*.png; do
    if ! python3 "$REPO/tools/pngink.py" "$f" --min "$MIN_INK" --skip-top "$SKIP_TOP" >/dev/null; then
      echo "  ⚠️  $(basename "$f") 几乎没有内容，多半没渲染出来"
      suspicious=$((suspicious+1))
    fi
  done
  echo "  共 $(ls "$dest"/*.png | wc -l | tr -d ' ') 张，可疑 $suspicious 张"
}

case "$mode" in
  render)     render "$CURRENT";  echo "✅ → $CURRENT" ;;
  --baseline) render "$BASELINE"; echo "✅ $PREFIX 基线已更新 → $BASELINE" ;;
  --compare)
    [ -d "$BASELINE" ] || { echo "❌ 还没有 $PREFIX 基线，先跑 --baseline" >&2; exit 1; }
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
    # 所以这两端「有差异」是常态，图要人（或 agent）自己看，不能只看计数。
    [ "$changed" -eq 0 ] || echo "  注意：状态栏时钟每分钟都在变，逐字节比对必然报差异；这份清单只用来定位该看哪几张。"
    ;;
esac
