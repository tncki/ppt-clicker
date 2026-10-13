#!/bin/bash
#
# PPT Clicker 安装脚本
#
#   curl -fsSL https://raw.githubusercontent.com/tncki/ppt-clicker/main/install.sh | bash
#
# 为什么不弹 Gatekeeper：脚本用 curl 下载（浏览器下载才会被标记隔离属性），
# 并且额外清一次 quarantine，所以打开即用，不需要任何"仍要打开"的手动放行。
#
# 可用环境变量（也方便本地测试）：
#   VERSION=2.0.0        指定版本（默认取最新 Release）
#   DEST=~/Applications  安装位置（默认 /Applications，不可写时自动退到 ~/Applications）
#
set -euo pipefail

REPO="tncki/ppt-clicker"
APP_NAME="PPTClicker.app"
VERSION="${VERSION:-}"
DEST="${DEST:-/Applications}"

say() { printf '  %s\n' "$*"; }
fail() { printf '\n✗ %s\n' "$*" >&2; exit 1; }

echo "PPT Clicker 安装脚本"

[[ "$(uname -s)" == "Darwin" ]] || fail "只支持 macOS。"

# ── 1. 确定版本 ────────────────────────────────────────────────
if [[ -z "$VERSION" ]]; then
  say "查询最新版本…"
  VERSION=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
    "https://github.com/$REPO/releases/latest" 2>/dev/null | sed 's|.*/tag/||')
  [[ -n "$VERSION" ]] || fail "无法获取最新版本，请手动指定：VERSION=2.0.0 bash install.sh"
fi
say "版本：$VERSION"

# ── 2. 下载并校验 ──────────────────────────────────────────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ZIP="PPT-Clicker-${VERSION#v}.zip"
BASE="https://github.com/$REPO/releases/download/$VERSION"

say "下载 $ZIP …"
curl -fL --progress-bar -o "$TMP/$ZIP" "$BASE/$ZIP" || fail "下载失败：$BASE/$ZIP"

say "校验 SHA256 …"
curl -fsSL -o "$TMP/SHA256SUMS.txt" "$BASE/SHA256SUMS.txt" \
  || fail "无法获取 SHA256SUMS.txt，已中止（不校验就安装不安全）"
EXPECTED=$(grep " $ZIP\$" "$TMP/SHA256SUMS.txt" | awk '{print $1}')
ACTUAL=$(shasum -a 256 "$TMP/$ZIP" | awk '{print $1}')
[[ -n "$EXPECTED" && "$EXPECTED" == "$ACTUAL" ]] || fail "校验和不匹配（期望 ${EXPECTED:-无}，实际 $ACTUAL）"
say "校验通过：${ACTUAL:0:16}…"

# ── 3. 解压 ────────────────────────────────────────────────────
ditto -x -k "$TMP/$ZIP" "$TMP/extract" || fail "解压失败"
[[ -d "$TMP/extract/$APP_NAME" ]] || fail "压缩包里没有 $APP_NAME"
NEW_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "$TMP/extract/$APP_NAME/Contents/Info.plist" 2>/dev/null || echo "?")

# ── 4. 安装 ────────────────────────────────────────────────────
if [[ ! -d "$DEST" ]] || [[ ! -w "$DEST" ]]; then
  say "$DEST 不可写，改装到 ~/Applications"
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

if pgrep -f "$APP_NAME/Contents/MacOS/PPTClicker" >/dev/null 2>&1; then
  say "先退出正在运行的旧版本…"
  pkill -f "$APP_NAME/Contents/MacOS/PPTClicker" 2>/dev/null || true
  sleep 1
fi

rm -rf "$DEST/$APP_NAME"
ditto "$TMP/extract/$APP_NAME" "$DEST/$APP_NAME" || fail "写入 $DEST 失败"
# 双保险：即使被标记过隔离，也清掉
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true

say "已安装：$DEST/$APP_NAME（版本 $NEW_VERSION）"

# ── 5. 打开并给出下一步 ────────────────────────────────────────
open "$DEST/$APP_NAME" 2>/dev/null || true

cat <<'EOF'

接下来三步：

  1. 首次打开会请求「辅助功能」权限 —— 在系统设置里把 PPT Clicker 打开
     （拦截鼠标必需；想要按 ESC 关闭，再把「输入监控」也打开）
  2. 放映 PPT 时，双击鼠标滚轮键开启 —— 屏幕右上角的小圆点变绿
  3. 左键 / 滚轮向下 = 下一页   右键 / 滚轮向上 = 上一页
     关闭：按 ESC、再双击滚轮键、或按 ⌃⌥⌘P

菜单栏图标和角落小圆点里都有完整菜单。
卸载：删掉 App，再删 ~/Library/Application Support/PPTClicker 即可。
EOF
