#!/usr/bin/env bash
# try-sim.sh — 在模拟器里打开 iPhone / Apple Watch 版，用你自己的 vault。
#
#   bash tools/try-sim.sh iphone          # 用真实 vault（读配置里的 vault 路径）
#   bash tools/try-sim.sh watch
#   bash tools/try-sim.sh iphone --demo   # 改用仓库自带的示例数据
#
# 与 tools/snapshot-sim.sh 的分工：那个是给自动化截图用的（每张都冷启动、
# 铺确定性夹具）；这个是**给人用的**——开机、装好、把你的真实笔记放进去、
# 把模拟器窗口叫到前台，然后就交给你自己点。
#
# 为什么必须走模拟器：真机安装要签名身份，`security find-identity -p codesigning`
# 目前是 0 个。要装到你自己的 iPhone/Watch 上，见 README 的「装到真机」一节。
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO/apple/LifeOSApp"

platform="${1:-}"
use_demo=false
[ "${2:-}" = "--demo" ] && use_demo=true

case "$platform" in
  iphone)
    SCHEME=LifeOS-iOS; BUNDLE_ID=com.lifeos.workflow
    RUNTIME=iOS;       PREFERRED='iPhone 17 Pro' ;;
  watch)
    SCHEME=LifeOS-watchOS; BUNDLE_ID=com.lifeos.workflow.watchkitapp
    RUNTIME=watchOS;       PREFERRED='Apple Watch Series 11 (46mm)' ;;
  *)
    echo "用法：bash tools/try-sim.sh <iphone|watch> [--demo]" >&2; exit 2 ;;
esac

# ---------- 找一台设备，没开就开 ----------
DEV=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
booted = named = first = ''
for runtime, items in devices.items():
    if '$RUNTIME' not in runtime:
        continue
    for d in items:
        if d['state'] == 'Booted': booted = booted or d['udid']
        if d['name'] == '''$PREFERRED''': named = named or d['udid']
        first = first or d['udid']
print(booted or named or first)
")
[ -n "$DEV" ] || { echo "❌ 找不到 $RUNTIME 模拟器，先在 Xcode 里装一个" >&2; exit 1; }
xcrun simctl bootstatus "$DEV" -b >/dev/null 2>&1 || xcrun simctl boot "$DEV" >/dev/null 2>&1 || true
open -a Simulator
echo "模拟器 $DEV 已就绪"

# ---------- 构建 ----------
command -v xcodegen >/dev/null || { echo "❌ 需要 xcodegen（brew install xcodegen）" >&2; exit 1; }
( cd "$APP_DIR" && xcodegen generate >/dev/null )
DD="$REPO/.snapshots/DerivedData-try"
echo "构建中…（首次会久一点）"
set -o pipefail
if ! ( cd "$APP_DIR" && xcodebuild -project LifeOS.xcodeproj -scheme "$SCHEME" \
        -configuration Debug -destination "id=$DEV" -derivedDataPath "$DD" -quiet build ) \
        > /tmp/try-sim-build.log 2>&1; then
  echo "❌ 构建失败，见 /tmp/try-sim-build.log" >&2
  grep -E 'error:' /tmp/try-sim-build.log | head -10 >&2 || true
  exit 1
fi
# 产物按 target 段落取：iOS 的构建目录里同时躺着 iPhone 应用和被嵌入的手表应用
APP=$( cd "$APP_DIR" && xcodebuild -project LifeOS.xcodeproj -scheme "$SCHEME" \
        -configuration Debug -destination "id=$DEV" -derivedDataPath "$DD" \
        -showBuildSettings 2>/dev/null | awk -F' = ' -v want="$SCHEME" '
          /^Build settings for action build and target / {
              t=$0; sub(/.*target /,"",t); sub(/:.*/,"",t); cur=(t==want); next }
          cur && /  TARGET_BUILD_DIR = /  { dir=$2 }
          cur && /  FULL_PRODUCT_NAME = / { name=$2 }
          END { if (dir && name) print dir "/" name }' )
xcrun simctl install "$DEV" "$APP" >/dev/null

# ---------- 放数据 ----------
# 模拟器读不到宿主机的 iCloud Drive，所以把 vault 复制进 App 容器。
# 这是**单向快照**：在模拟器里改的东西不会回到你的 iCloud。
CONTAINER=$(xcrun simctl get_app_container "$DEV" "$BUNDLE_ID" data)
VAULT="$CONTAINER/Documents/LifeOSVault"
rm -rf "$VAULT"; mkdir -p "$VAULT"
if $use_demo; then
  mkdir -p "$VAULT/Inbox" "$VAULT/Projects"
  cp -R "$REPO/seed/vault/." "$VAULT/"
  cp "$REPO"/seed/examples/Inbox/*.md    "$VAULT/Inbox/"
  cp "$REPO"/seed/examples/Projects/*.md "$VAULT/Projects/"
  echo "已放入示例数据"
else
  REAL=$(cd "$REPO" && python3 -c 'from lifeos.config import get_config; print(get_config().vault)')
  if [ -d "$REAL" ]; then
    rsync -a --exclude '.git*' --exclude '.DS_Store' "$REAL"/ "$VAULT"/
    echo "已放入你的 vault：$(find "$VAULT" -name '*.md' | wc -l | tr -d ' ') 个文件"
    echo "  来源 $REAL"
    echo "  ⚠️  这是单向复制——在模拟器里改的内容不会回到 iCloud"
  else
    echo "⚠️  读不到 vault（$REAL），改用示例数据" >&2
    mkdir -p "$VAULT/Inbox" "$VAULT/Projects"
    cp -R "$REPO/seed/vault/." "$VAULT/"
    cp "$REPO"/seed/examples/Inbox/*.md    "$VAULT/Inbox/"
    cp "$REPO"/seed/examples/Projects/*.md "$VAULT/Projects/"
  fi
fi

xcrun simctl launch "$DEV" "$BUNDLE_ID" >/dev/null
echo "✅ 已在模拟器里打开，去 Simulator 窗口里点吧"
