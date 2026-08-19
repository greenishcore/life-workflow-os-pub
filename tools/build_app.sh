#!/usr/bin/env bash
# build_app.sh — 打包成可双击运行的 macOS 应用（dist/Life Workflow OS.app）
#
# 这是一个「启动器型」应用包：代码与数据仍在本仓库，.app 负责被 Finder/
# 启动台识别、带图标、并申请 AppleScript 自动化权限。这样你 git pull 更新
# 代码后，应用立即是新版本，不需要重新打包。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Life Workflow OS"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
VERSION="$(sed -n 's/^APP_VERSION = "\(.*\)"/\1/p' "$ROOT/lifeos/gui/app.py" | head -1)"
VERSION="${VERSION:-1.0.0}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 图标（缺了就现生成）
[[ -f "$ROOT/assets/AppIcon.icns" ]] || python3 "$ROOT/tools/make_icon.py" || true
[[ -f "$ROOT/assets/AppIcon.icns" ]] && cp "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>com.lifeos.workflow</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>LifeWorkflowOS</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>用于把「提醒事项」「日历」「备忘录」的内容导入到你的本地 Markdown 知识库。</string>
  <key>NSRemindersUsageDescription</key>
  <string>用于把提醒事项导入到当天的 Daily 笔记。</string>
  <key>NSCalendarsUsageDescription</key>
  <string>用于把日历事件导入到当天的 Daily 笔记。</string>
</dict>
</plist>
PLIST

# 可执行入口：转交给仓库里的启动器（路径在打包时固化）
cat > "$APP/Contents/MacOS/LifeWorkflowOS" <<LAUNCHER
#!/bin/bash
# 由 tools/build_app.sh 生成。代码位置固化为打包时的仓库路径。
LIFEOS_ROOT="$ROOT"
if [[ ! -x "\$LIFEOS_ROOT/bin/lifeos" ]]; then
  osascript -e 'display alert "Life Workflow OS" message "找不到程序目录：'"$ROOT"'\n\n如果你移动过仓库，请重新运行 tools/build_app.sh 打包。" as critical'
  exit 1
fi
exec "\$LIFEOS_ROOT/bin/lifeos" 2>>"\$HOME/Library/Logs/LifeWorkflowOS.log"
LAUNCHER
chmod +x "$APP/Contents/MacOS/LifeWorkflowOS"

# 让 Finder 立刻刷新图标
touch "$APP"
echo "✅ 已生成 $APP"
echo "   双击运行，或： open -a \"$APP_NAME\""
echo "   放进启动台： ln -sfn \"$APP\" /Applications/"
