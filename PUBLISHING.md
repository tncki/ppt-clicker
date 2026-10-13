# 发布与维护指引

仓库：<https://github.com/tncki/ppt-clicker>　维护者：[@tncki](https://github.com/tncki)

当前状态：本地已有完整 git 历史，SSH 推送可用（`ssh -T git@github.com` → `Hi tncki!`），
只差在 GitHub 上创建仓库。

## 首次发布

### 1. 在 GitHub 创建空仓库

打开 <https://github.com/new>：

- **Repository name**：`ppt-clicker`
- **不要**勾选 Add README / .gitignore / license（本地已经有内容，勾了会冲突）
- 可见性建议 **Public**

### 2. 推送

```bash
cd /Users/jack/workspace/ppt-clicker
git remote add origin git@github.com:tncki/ppt-clicker.git
git branch -M main
git push -u origin main
```

推送后 CI（`.github/workflows/ci.yml`）会自动编译并跑 89 项自测，首页徽章会变绿。

### 3. 打标签发版

CI 会自动构建通用二进制（arm64 + x86_64）、打包 zip/dmg 并创建 Release：

```bash
git tag v2.0.0
git push origin v2.0.0
```

`release.yml` 会做四件事：

1. 校验 tag 与 `Info.plist` 的版本号一致（不一致直接失败，避免发错版本）
2. `./release.sh` 构建 arm64 + x86_64 通用二进制并打包
3. 生成 `SHA256SUMS.txt`
4. 创建 GitHub Release 并上传产物

## 后续版本

1. 改 `Info.plist` 里的 `CFBundleShortVersionString`（和 `CFBundleVersion`）
2. 更新 `CHANGELOG.md`
3. 本地验证：`./build.sh`（89 项自测）+ 手动跑一遍四种开关
4. `git commit` → `git push` → `git tag vX.Y.Z` → `git push origin vX.Y.Z`

## 本地构建

```bash
./build.sh                 # 本机架构 + 自测
./build.sh --universal     # 通用二进制
./release.sh               # 通用二进制 + zip + dmg + SHA256SUMS.txt
```

> 注意：沙箱环境里 `hdiutil` 无法创建挂载点，本地只出 zip；GitHub Actions 不受限，会同时产出 dmg。

## Homebrew

`packaging/homebrew/ppt-clicker.rb` 是 cask 模板。每次发版后：

```bash
shasum -a 256 dist/PPT-Clicker-<版本>.zip     # 填进 cask 的 sha256
```

放进自己的 tap 仓库（`homebrew-tap/Casks/ppt-clicker.rb`）后，用户就能：

```bash
brew install --cask tncki/tap/ppt-clicker
```

## 关于签名与公证

发布包是**临时签名（ad-hoc）**，用户首次打开需要在
「系统设置 → 隐私与安全性 → 仍要打开」，或执行一次
`xattr -dr com.apple.quarantine "/Applications/PPTClicker.app"`。

想彻底消除这一步需要 Apple 开发者账号（$99/年）：

1. 生成 *Developer ID Application* 证书并导出 `.p12`
2. 把 `.p12`、密码、Apple ID、Team ID、App 专用密码放进仓库 Secrets
3. 在 `.github/workflows/release.yml` 打包步骤后加导入证书 + 签名 + 公证：

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

   同时把 `build.sh` 里的 `codesign --sign -` 换成正式证书。

## 维护备忘

- **bundle id**：`io.github.pptclicker`（中性，无需自有域名）。若改成 `com.<你的域名>.*`，用户需要重新授权辅助功能。
- **目录不能动**：App 放在哪个目录，辅助功能授权和开机自启就绑在哪里；移动后要重新授权。
- **代码注释与日志是中文**，界面文案走 `L.s(...)` 双语表（见 `Sources/Localization.swift`）。
