# Homebrew cask 模板
#
# 用法（发布 Release 之后）：
#   1. 把下面的 <owner> 换成你的 GitHub 用户名，<version> 换成版本号；
#   2. 填入 release 包的真实 sha256（shasum -a 256 PPT-Clicker-<version>.zip）；
#   3. 放进你自己的 tap 仓库（homebrew-tap/Casks/ppt-clicker.rb）后即可：
#        brew install --cask <owner>/tap/ppt-clicker
#   4. 想进官方 homebrew-cask，需要先在 GitHub 上有一定关注度，再提 PR。

cask "ppt-clicker" do
  version "<version>"
  sha256 "<sha256-of-zip>"

  url "https://github.com/<owner>/ppt-clicker/releases/download/v#{version}/PPT-Clicker-#{version}.zip"
  name "PPT Clicker"
  desc "Turn any mouse into a presentation clicker"
  homepage "https://github.com/<owner>/ppt-clicker"

  # 未公证，装完需要用户手动放行一次
  caveats <<~EOS
    PPT Clicker is not notarized. On first launch either right-click → Open,
    or run:
      xattr -dr com.apple.quarantine "#{appdir}/PPTClicker.app"
    Then grant Accessibility permission (System Settings → Privacy & Security).
  EOS

  app "PPTClicker.app"

  uninstall launchctl: "io.github.pptclicker"
end
