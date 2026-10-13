# 发布与维护指引

仓库：<https://github.com/tncki/ppt-clicker>　维护者：[@tncki](https://github.com/tncki)

当前状态：**已发布** v2.0.0 —— 仓库 <https://github.com/tncki/ppt-clicker>、
Release <https://github.com/tncki/ppt-clicker/releases/tag/v2.0.0>，CI 与发版工作流均已跑通。
下面保留首次发布的步骤作为记录。

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

**两个平台各有自己的版本号，必须同时改，否则 tag 校验会失败：**

| 平台 | 位置 |
| --- | --- |
| macOS | `Info.plist` 的 `CFBundleShortVersionString`（和 `CFBundleVersion`） |
| Windows | `windows/PPTClicker.csproj` 的 `<Version>` |

步骤：

1. 改上面两处版本号 + `CHANGELOG.md`
2. 本地验证：`./build.sh`（89 项自测）；Windows 改动能过 CI 的 `--selftest` + `--hooktest`
3. `git commit` → `git push`（等 CI 绿）→ `git tag vX.Y.Z` → `git push origin vX.Y.Z`
4. `./tools/update-cask.sh` 同步 cask 的校验和并提交

## 发布产物

`v*` tag 会由 `.github/workflows/release.yml` 同时产出：

| 文件 | 平台 | 说明 |
| --- | --- | --- |
| `PPT-Clicker-<v>.zip` / `.dmg` | macOS | 通用二进制（arm64 + x86_64） |
| `PPT-Clicker-<v>-win-x64.zip` | Windows | 自包含单文件 exe，约 56 MB（目标机器无需装 .NET） |
| `SHA256SUMS.txt` / `SHA256SUMS-windows.txt` | 两者 | 校验和 |

两个平台的包**都没有代码签名**：

- macOS：`install.sh` / Homebrew 用 curl 下载，不带隔离属性，不需要 Gatekeeper 放行；手动下载需 `xattr -dr`
- Windows：`install.ps1` 解压后调用 `Unblock-File` 清掉 Internet 标记，不弹 SmartScreen；手动下载需 `Unblock-File`

## 本地构建

```bash
./build.sh                 # 本机架构 + 自测
./build.sh --universal     # 通用二进制
./release.sh               # 通用二进制 + zip + dmg + SHA256SUMS.txt
```

> 注意：沙箱环境里 `hdiutil` 无法创建挂载点，本地只出 zip；GitHub Actions 不受限，会同时产出 dmg。

## 安装渠道（三条，都不需要 Apple 开发者账号）

| 渠道 | 是否弹 Gatekeeper | 说明 |
| --- | --- | --- |
| `Casks/ppt-clicker.rb`（Homebrew） | **不弹** | cask 用 curl 下载，不带隔离属性 |
| `install.sh`（一行脚本） | **不弹** | 同上，并且额外校验 SHA256、清一次 quarantine |
| 手动下载 zip/dmg | 会弹 | 浏览器会给文件打隔离标记，需 `xattr -dr com.apple.quarantine` 放行一次 |

实测依据（本机 macOS 26.6）：

```
curl 下载的 zip / 解压出的 App → xattr 无 quarantine 属性 → 直接启动
spctl -a -t exec 判定 rejected（未公证），但只要没隔离标记就不会被拦
```

### cask 维护（发版后必须做）

`Casks/ppt-clicker.rb` 里的 `sha256` **必须对应 Release 上真实发布的 zip**——
本地 `./release.sh` 打出的包字节不同、校验和也不同，所以不要在本地手填。

发版后跑一次专用脚本，它会下载官方 `SHA256SUMS.txt`、**重新下载并核对** zip，
再写回 cask：

```bash
./tools/update-cask.sh          # 取最新 Release
./tools/update-cask.sh 2.0.1    # 或指定版本
git add Casks/ppt-clicker.rb && git commit -m "chore: cask 2.0.1"
```

用户端：

```bash
brew tap tncki/ppt-clicker https://github.com/tncki/ppt-clicker
brew install --cask ppt-clicker
brew upgrade --cask ppt-clicker     # 升级；zap 可连配置一起清
```

## 关于公证：决定不做

本项目**不使用 Apple 开发者账号（$99/年）**，因此不做签名与公证。
这是明确的取舍，不是遗漏：

- 代价：手动下载 zip 的用户需要执行一次 `xattr` 放行命令（文案已写在 README 与 Release 说明里）
- 缓解：`install.sh` 与 Homebrew 两条路径用 curl 下载，用户完全无感
- 另外：App 用临时签名，**重新编译后辅助功能授权会失效**（macOS 按二进制指纹记权限）。
  这是自用/开发时的已知不便；普通用户只在升级版本时会遇到一次。

如果哪天改变主意，公证步骤见 git 历史里 2026-10-13 之前的版本，或按下面的要点做：
生成 *Developer ID Application* 证书 → 放进仓库 Secrets → 在 `release.yml` 里
导入证书 + `codesign --options runtime` + `notarytool submit --wait` + `stapler staple`。

## 维护备忘

- **bundle id**：`io.github.pptclicker`（中性，无需自有域名）。若改成 `com.<你的域名>.*`，用户需要重新授权辅助功能。
- **目录不能动**：App 放在哪个目录，辅助功能授权和开机自启就绑在哪里；移动后要重新授权。
- **代码注释与日志是中文**，界面文案走 `L.s(...)` 双语表（见 `Sources/Localization.swift`）。
