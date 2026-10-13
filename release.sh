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
: > "$DIST/SHA256SUMS.txt"
if [[ $DMG_OK == 1 && -f "$DIST/$NAME.dmg" ]]; then
  (cd "$DIST" && shasum -a 256 "$NAME.dmg") >> "$DIST/SHA256SUMS.txt"
fi
(cd "$DIST" && shasum -a 256 "$NAME.zip") >> "$DIST/SHA256SUMS.txt"

echo ""
cat "$DIST/SHA256SUMS.txt"
echo ""
echo "发布包就绪："
[[ $DMG_OK == 1 ]] && echo "  $DIST/$NAME.dmg"
echo "  $DIST/$NAME.zip"
echo ""
echo "提示 1：本地包的校验和 ≠ Release 上的包（打包字节不同），"
echo "        cask 请用 tools/update-cask.sh 从已发布的 Release 同步。"
echo "提示 2：本包为免公证的临时签名，但用 curl/Homebrew 安装不会被 Gatekeeper 拦；"
echo "        浏览器直接下载的解压后需执行一次："
echo "        xattr -dr com.apple.quarantine \"/Applications/PPTClicker.app\""
