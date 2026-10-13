#!/bin/bash
# 构建 PPT Clicker.app
#
#   ./build.sh               本机架构（开发用，快）
#   ./build.sh --universal   arm64 + x86_64 通用二进制（用于发布）
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
APP="$DIST/PPTClicker.app"
INFO="$ROOT/Info.plist"

UNIVERSAL=0
[[ "${1:-}" == "--universal" ]] && UNIVERSAL=1

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO")
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO")

rm -rf "$BUILD" "$APP"
mkdir -p "$BUILD/tmp" "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 沙箱/CI 环境下编译器临时目录与模块缓存要可控
export TMPDIR="$BUILD/tmp"

ARCHS=(arm64)
[[ $UNIVERSAL == 1 ]] && ARCHS=(arm64 x86_64)

BINS=()
for ARCH in "${ARCHS[@]}"; do
  echo "==> 编译 $ARCH"
  swiftc -O -swift-version 5 \
    -target "${ARCH}-apple-macos13.0" \
    -module-cache-path "$BUILD/modulecache-$ARCH" \
    -framework AppKit \
    -framework CoreGraphics \
    -framework ApplicationServices \
    "$ROOT"/Sources/*.swift \
    -o "$BUILD/PPTClicker-$ARCH"
  BINS+=("$BUILD/PPTClicker-$ARCH")
done

if [[ ${#BINS[@]} -gt 1 ]]; then
  echo "==> 合并通用二进制"
  lipo -create -output "$BUILD/PPTClicker" "${BINS[@]}"
  lipo -info "$BUILD/PPTClicker"
else
  cp "${BINS[0]}" "$BUILD/PPTClicker"
fi

echo "==> 打包 v$VERSION"
cp "$BUILD/PPTClicker" "$APP/Contents/MacOS/PPTClicker"
cp "$INFO" "$APP/Contents/Info.plist"
[[ -f "$ROOT/Resources/AppIcon.icns" ]] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# 临时签名：本地运行足够；要发布给公众需要开发者证书+公证（见 README）
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" 2>/dev/null \
  || echo "  警告：codesign 失败，仍可运行"

echo "==> 自测"
"$APP/Contents/MacOS/PPTClicker" --selftest

echo ""
echo "完成：$APP  (v$VERSION)"
