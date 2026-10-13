# Changelog

## Unreleased

- 新增 `install.sh` 一行安装脚本：下载最新 Release、校验 SHA256、装到 `/Applications`，
  因为用 `curl` 下载不带隔离属性，用户不会被 Gatekeeper 拦
- 新增 `Casks/ppt-clicker.rb`：可直接 `brew tap tncki/ppt-clicker <本仓库>` 安装
- `release.sh` 发版时自动同步 cask 的版本号与校验和
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
