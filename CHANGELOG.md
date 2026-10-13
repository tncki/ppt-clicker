# Changelog

## 2.1.0

**新增 Windows 版**（与 macOS 版功能对齐，各自独立实现）：

- Windows 用 `SetWindowsHookEx(WH_MOUSE_LL)` 低级鼠标钩子拦截 + `SendInput` 合成按键
- 托盘菜单、屏幕角落指示灯（绿=开启/灰=关闭/橙=钩子异常）、四种开关方式同上
- 全局快捷键默认 `Ctrl+Alt+Shift+P`；ESC 用低级键盘钩子**只旁听**，不影响 PowerPoint 自己退出放映
- 无需任何系统权限，也不需要管理员身份；开机自启写注册表 Run 项
- 自包含单文件 exe（win-x64），目标机器无需安装 .NET
- 配置格式与 macOS 版一致（`apps` 用 exe 名而不是 bundleID），路径在 `%APPDATA%\PPTClicker\config.json`
- 两套自检都在 CI 上跑：纯逻辑 89 项 + **钩子链路自检**（合成一次左键，验证被拦截并发出 → 键）
- 新增 `install.ps1`：PowerShell 一行安装，并 `Unblock-File` 清掉 Internet 标记，不弹 SmartScreen
- 发版流程改为三平台统一：`v*` tag 会同时产出 macOS zip/dmg 与 Windows zip

## Unreleased

- 新增 `install.sh` 一行安装脚本：下载最新 Release、校验 SHA256、装到 `/Applications`，
  因为用 `curl` 下载不带隔离属性，用户不会被 Gatekeeper 拦
- 新增 `Casks/ppt-clicker.rb`：可直接 `brew tap tncki/ppt-clicker <本仓库>` 安装
- 新增 `tools/update-cask.sh`：从已发布的 Release 下载并核对 zip 后同步 cask
  （本地构建的包与发布包校验和不同，必须从 Release 同步）
- 明确采用「不做 Apple 公证」策略，文档改为以免弹窗安装方式为主

## 2.0.0

首个公开发布版本。

- 用任意鼠标当翻页笔：左键 / 滚轮下 = 下一页，右键 / 滚轮上 = 上一页
- 屏幕角落常驻指示灯（绿点 = 已开启），可点击开关、拖动换位置
- 四种开关方式：全局快捷键、双击滚轮键、ESC、点指示灯
- 滚轮方向**自动适配**系统「自然滚动」设置，换机器不用改配置
- 全部映射可在 JSON 里自定义（中键、侧键、黑屏/白屏键等）
- 菜单栏工具：权限状态、原始事件诊断、开机自启、一键打开配置
- 89 项无界面自测（`./build.sh` 自动运行）
- 通用二进制（ Apple Silicon + Intel），GitHub Actions 自动构建发布

## 1.0.0

本机自用版本（未发布）。

- HID 层拦截鼠标事件并合成按键
- 惯性滚动过滤 + 连发节流
- 鼠标通道自检
- 系统 `RegisterEventHotKey` 全局快捷键
- 指示灯 + ESC / 双击滚轮键关闭
