#!/bin/bash
# 从已发布的 GitHub Release 同步 Homebrew cask 的 version / sha256
#
#   ./tools/update-cask.sh            # 取最新 Release
#   ./tools/update-cask.sh 2.0.1      # 指定版本
#
# 注意：cask 里的 sha256 必须对应 **Release 上真实发布的 zip**，
# 不能用本地 ./release.sh 产出的包（两次打包的字节不同，校验和自然不同）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CASK="$ROOT/Casks/ppt-clicker.rb"
REPO="tncki/ppt-clicker"
VERSION="${1:-}"

[[ -f "$CASK" ]] || { echo "找不到 $CASK"; exit 1; }

if [[ -z "$VERSION" ]]; then
  echo "==> 查询最新 Release"
  VERSION=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
    "https://github.com/$REPO/releases/latest" | sed 's|.*/tag/||')
  [[ -n "$VERSION" ]] || { echo "无法获取最新版本，请手动指定"; exit 1; }
fi
VERSION="${VERSION#v}"

BASE="https://github.com/$REPO/releases/download/v$VERSION"
ZIP="PPT-Clicker-$VERSION.zip"

echo "==> 下载官方校验和：$BASE/SHA256SUMS.txt"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/SHA256SUMS.txt" "$BASE/SHA256SUMS.txt"

SHA=$(awk -v f="$ZIP" '$2 == f { print $1; exit }' "$TMP/SHA256SUMS.txt")
[[ -n "$SHA" ]] || { echo "SHA256SUMS.txt 里没有 $ZIP"; cat "$TMP/SHA256SUMS.txt"; exit 1; }

echo "==> 下载发布包并核对校验和"
curl -fsSL -o "$TMP/$ZIP" "$BASE/$ZIP"
ACTUAL=$(shasum -a 256 "$TMP/$ZIP" | awk '{print $1}')
if [[ "$ACTUAL" != "$SHA" ]]; then
  echo "✗ 下载的包与官方校验和不符（期望 $SHA，实际 $ACTUAL）"; exit 1
fi
echo "    ✓ 校验通过 ${SHA:0:16}…"

echo "==> 更新 $CASK"
/usr/bin/sed -i '' \
  -e "s/^  version \".*\"/  version \"$VERSION\"/" \
  -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
  "$CASK"
grep -E '^  (version|sha256)' "$CASK"

echo ""
echo "完成。记得提交："
echo "  git add Casks/ppt-clicker.rb && git commit -m \"chore: cask $VERSION\""
