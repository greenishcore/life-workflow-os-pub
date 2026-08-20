#!/usr/bin/env bash
# setup-signing.sh — 配好真机安装需要的签名。
#
#   bash tools/setup-signing.sh              # 自动从钥匙串里读出 Team ID
#   bash tools/setup-signing.sh ABCDE12345   # 或手动指定（10 位 Team ID）
#
# 前提：Xcode → Settings → Accounts 里已经加了 Apple ID（**免费账号就够**）。
# 加完之后 Xcode 会自动签发一张 Apple Development 证书，Team ID 就在它的
# Organizational Unit 字段里，这个脚本把它读出来写进 Signing.local.xcconfig。
#
# 写的是本地文件而不是直接改 project.yml，因为 project.yml 要进公开仓库。
# Team ID 不是密钥（没有私钥签不了任何东西），但它绑定你的身份，不该带出去。
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$REPO/apple/LifeOSApp/Signing.local.xcconfig"

team="${1:-}"
if [ -z "$team" ]; then
  # 证书 subject 里的 OU 就是 Team ID：
  #   subject=UID=…, CN=Apple Development: 你@邮箱 (…), OU=ABCDE12345, O=…, C=US
  team=$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
         | openssl x509 -noout -subject 2>/dev/null \
         | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1)
fi

if [ -z "$team" ]; then
  echo "❌ 没找到开发团队。" >&2
  echo >&2
  echo "   先在 Xcode 里加一个 Apple ID（免费账号即可）：" >&2
  echo "     Xcode → Settings → Accounts → 左下角 + → Apple ID" >&2
  echo >&2
  echo "   加完之后再跑一次本脚本；或者直接把 Team ID 传进来：" >&2
  echo "     bash tools/setup-signing.sh <你的10位TeamID>" >&2
  exit 1
fi

cat > "$TARGET" <<EOF
// 本地签名配置（已 gitignore，不要提交）
// 由 tools/setup-signing.sh 生成
LIFEOS_DEVELOPMENT_TEAM = $team
EOF

echo "✅ 开发团队 $team → $(basename "$TARGET")"
security find-identity -p codesigning -v 2>/dev/null | grep -c 'valid identities' >/dev/null && \
  security find-identity -p codesigning -v 2>/dev/null | head -2 | sed 's/^/   /'
echo
echo "接下来："
echo "   cd apple/LifeOSApp && xcodegen generate"
echo "   然后在 Xcode 里选真机 Run，或者："
echo "   xcodebuild -project apple/LifeOSApp/LifeOS.xcodeproj -scheme LifeOS-iOS \\"
echo "     -destination 'generic/platform=iOS' -derivedDataPath /tmp/dev-ios build"
echo "   xcrun devicectl device install app --device <设备UDID> <产物路径>"
echo
echo "⚠️  免费账号的描述文件 **7 天过期**，到期重新 Run 一次即可。"
