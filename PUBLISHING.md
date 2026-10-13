# 发布指引（仓库作者用）

这个目录已经是一个可以直接推上 GitHub 的完整仓库。按下面 4 步就能发布。

## 0. 先设置 git 身份

仓库里的初始提交用的是占位身份（这台机器没配过 git 用户名）。推之前先改成你自己的：

```bash
cd /Users/jack/workspace/ppt-clicker
git config user.name  "你的名字"
git config user.email "你的邮箱"
git commit --amend --reset-author --no-edit   # 把初始提交的作者改掉
```

## 1. 替换占位符

把下面文件里的 `tncki` 换成你的 GitHub 用户名（或组织名）：

```bash
cd /Users/jack/workspace/ppt-clicker
grep -rl "tncki" . --exclude-dir=.git --exclude-dir=build --exclude-dir=dist
```

需要改的位置：

| 文件 | 内容 |
| --- | --- |
| `README.md` / `README.zh-CN.md` | clone 地址、Releases 链接 |
| `packaging/homebrew/ppt-clicker.rb` | cask 的 url / homepage |
| `.github/workflows/*.yml` | 无需修改（用的是相对路径） |

另外可以顺手在 `README.md` 顶部加 CI 徽章：

```markdown
[![CI](https://github.com/tncki/ppt-clicker/actions/workflows/ci.yml/badge.svg)](https://github.com/tncki/ppt-clicker/actions/workflows/ci.yml)
```

> `Info.plist` 里的 bundle id 是 `io.github.pptclicker`（中性、无需域名）。如果你有自己的域名，可以改成 `com.yourdomain.pptclicker`，注意改完要重新授权一次辅助功能。

## 2. 建仓库并推送

```bash
cd /Users/jack/workspace/ppt-clicker

# 本地已经有初始提交；创建一个空仓库（不要勾选 README/.gitignore/LICENSE）
git remote add origin git@github.com:tncki/ppt-clicker.git
git branch -M main
git push -u origin main
```

## 3. 打标签发版

CI 会自动构建通用二进制、跑 89 项自测，并把 zip/dmg 传到 Release：

```bash
git tag v2.0.0
git push origin v2.0.0
```

工作流 `.github/workflows/release.yml` 会做四件事：

1. 校验 tag 与 `Info.plist` 里的版本号一致（不一致直接失败，避免发出错版本的包）
2. `./release.sh` 构建 arm64 + x86_64 通用二进制并打包
3. 生成 `SHA256SUMS.txt`
4. 创建 GitHub Release 并上传产物

## 4. 可选：Homebrew

`packaging/homebrew/ppt-clicker.rb` 是 cask 模板。发版后：

```bash
shasum -a 256 dist/PPT-Clicker-2.0.0.zip     # 填进 cask 的 sha256
```

把填好的 cask 放进你自己的 tap 仓库（`homebrew-tap/Casks/ppt-clicker.rb`），用户就能：

```bash
brew install --cask tncki/tap/ppt-clicker
```

## 关于签名与公证

当前发布包是**临时签名（ad-hoc）**，用户首次打开需要在
「系统设置 → 隐私与安全性 → 仍要打开」，或执行一次
`xattr -dr com.apple.quarantine "/Applications/PPTClicker.app"`。

如果你想彻底消除这一步，需要 Apple 开发者账号（$99/年）：

1. 在 Apple Developer 生成 *Developer ID Application* 证书，导出 `.p12`；
2. 把 `.p12` 与密码、Apple ID、Team ID、App 专用密码放进仓库 Secrets；
3. 在 `.github/workflows/release.yml` 的打包步骤后加：

   ```yaml
   - name: Import certificate
     env:
       CERT_P12: ${{ secrets.MACOS_CERT_P12 }}
       CERT_PASSWORD: ${{ secrets.MACOS_CERT_PASSWORD }}
     run: |
       echo "$CERT_P12" | base64 -d > cert.p12
       security create-keychain -p actions build.keychain
       security default-keychain -s build.keychain
       security unlock-keychain -p actions build.keychain
       security import cert.p12 -k build.keychain -P "$CERT_PASSWORD" -T /usr/bin/codesign
       security set-key-partition-list -S apple-tool:,apple: -s -k actions build.keychain

   - name: Sign, notarize and staple
     env:
       APPLE_ID: ${{ secrets.APPLE_ID }}
       APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
       APPLE_APP_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}
     run: |
       codesign --force --deep --options runtime --sign "Developer ID Application" dist/PPTClicker.app
       ditto -c -k --keepParent dist/PPTClicker.app /tmp/notarize.zip
       xcrun notarytool submit /tmp/notarize.zip --apple-id "$APPLE_ID" \
         --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
       xcrun stapler staple dist/PPTClicker.app
   ```

   然后 `./release.sh --no-build` 重新打包即可（注意 `build.sh` 里的 `codesign --sign -` 要换成正式证书）。
