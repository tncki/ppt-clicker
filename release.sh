#!/bin/bash
# 打发布包：通用二进制 + zip + dmg + SHA256
#
#   ./release.sh              编译（通用二进制）并打包
#   ./release.sh --no-build   跳过大编译，直接用现有 dist/PPTClicker.app 打包
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
APP="$DIST/PPTClicker.app"
INFO="$ROOT/Info.plist"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO")
NAME="PPT-Clicker-$VERSION"

if [[ "${1:-}" != "--no-build" ]]; then
  "$ROOT/build.sh" --universal
fi

[[ -d "$APP" ]] || { echo "找不到 $APP，请先编译"; exit 1; }

echo "==> 清理旧包"
rm -rf "$DIST/pkg" "$DIST/$NAME.zip" "$DIST/$NAME.dmg" "$DIST/SHA256SUMS.txt"
mkdir -p "$DIST/pkg"

echo "==> 制作 zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$NAME.zip"

echo "==> 制作 dmg"
STAGE="$DIST/pkg/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG_OK=0
if hdiutil create -volname "PPT Clicker" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$NAME.dmg" >/dev/null 2>&1; then
  DMG_OK=1
else
  # 受限环境（沙箱 / 无挂载权限）里 hdiutil 会失败，zip 不受影响
  echo "  注意：dmg 创建失败（当前环境不允许创建挂载点），已跳过；zip 正常"
fi

echo "==> 计算校验和"
(cd "$DIST" && { [[ $DMG_OK == 1 ]] && shasum -a 256 "$NAME.dmg"; shasum -a 256 "$NAME.zip"; } > SHA256SUMS.txt)

echo ""
cat "$DIST/SHA256SUMS.txt"
echo ""
echo "发布包就绪："
[[ $DMG_OK == 1 ]] && echo "  $DIST/$NAME.dmg"
echo "  $DIST/$NAME.zip"
echo ""
echo "提示：本包为临时签名，用户首次打开需在"
echo "  系统设置 → 隐私与安全性 → 仍要打开"
echo "或执行： xattr -dr com.apple.quarantine \"/Applications/PPT Clicker.app\""
