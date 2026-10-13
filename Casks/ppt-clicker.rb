# Homebrew cask（放在仓库根目录的 Casks/ 下，可直接 tap 本仓库）
#
# 用户安装：
#   brew tap tncki/ppt-clicker https://github.com/tncki/ppt-clicker
#   brew install --cask ppt-clicker
#
# 走 Homebrew 的好处：cask 用 curl 下载，不会带 quarantine 属性，
# 所以不会弹 Gatekeeper 的"无法验证开发者"。
#
# 发版后更新：./release.sh 会自动刷新下面的 version / sha256
cask "ppt-clicker" do
  version "2.0.0"
  sha256 "0c42d628c35a78f138cfe6d4f679c8131cf4a2912e10830367f2b34ae4101730"

  url "https://github.com/tncki/ppt-clicker/releases/download/v#{version}/PPT-Clicker-#{version}.zip"
  name "PPT Clicker"
  desc "Turn any mouse into a presentation clicker"
  homepage "https://github.com/tncki/ppt-clicker"

  app "PPTClicker.app"

  # 开机自启是 App 自己写的 LaunchAgent，卸载时一并清掉
  uninstall launchctl: "io.github.pptclicker"

  zap trash: [
    "~/Library/Application Support/PPTClicker",
    "~/Library/Logs/PPTClicker.log",
    "~/Library/Saved Application State/io.github.pptclicker.savedState",
  ]

  caveats <<~EOS
    PPT Clicker 需要「辅助功能」权限才能拦截鼠标事件：
      系统设置 → 隐私与安全性 → 辅助功能 → 打开 PPT Clicker
    想要按 ESC 关闭翻页笔模式，再打开「输入监控」。

    用法：放映时双击鼠标滚轮键开启（右上角小圆点变绿），
          左键/滚轮向下=下一页，右键/滚轮向上=上一页。
  EOS
end
