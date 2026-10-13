# PPT Clicker 安装脚本（Windows）
#
#   irm https://raw.githubusercontent.com/tncki/ppt-clicker/main/install.ps1 | iex
#
# 为什么不会弹 SmartScreen：用 PowerShell 下载后脚本会再 Unblock-File 一次
# （浏览器下载才会留下"来自 Internet"标记），所以打开即用。
#
# 可用环境变量：
#   $env:PPTCLICKER_VERSION = "2.1.0"                 指定版本
#   $env:PPTCLICKER_DEST    = "D:\Tools\PPTClicker"   安装目录
#
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo = "tncki/ppt-clicker"
$version = $env:PPTCLICKER_VERSION
$dest = if ($env:PPTCLICKER_DEST) { $env:PPTCLICKER_DEST } else { Join-Path $env:LOCALAPPDATA "PPTClicker" }

function Say([string]$message) { Write-Host "  $message" }

Write-Host "PPT Clicker 安装脚本"

if (-not $version) {
    Say "查询最新版本…"
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" `
        -Headers @{ "User-Agent" = "ppt-clicker-installer" }
    $version = $release.tag_name
}
if (-not $version) { throw "无法获取最新版本，请手动指定：`$env:PPTCLICKER_VERSION = '2.1.0'" }
Say "版本：$version"

$zipName = "PPT-Clicker-$($version.TrimStart('v'))-win-x64.zip"
$base = "https://github.com/$repo/releases/download/$version"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("pptclicker-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    $zipPath = Join-Path $tmp $zipName
    Say "下载 $zipName …"
    Invoke-WebRequest -Uri "$base/$zipName" -OutFile $zipPath -UseBasicParsing

    Say "校验 SHA256 …"
    try {
        $sums = (Invoke-WebRequest -Uri "$base/SHA256SUMS-windows.txt" -UseBasicParsing).Content
        $line = ($sums -split "`n") | Where-Object { $_ -match [regex]::Escape($zipName) } | Select-Object -First 1
        $expected = ($line -split '\s+')[0]
        if ($expected) {
            $actual = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
            if ($expected.ToLower() -ne $actual) { throw "校验和不匹配（期望 $expected，实际 $actual）" }
            Say "校验通过：$($actual.Substring(0, 16))…"
        } else {
            Say "（校验和文件里没有这个包，跳过）"
        }
    } catch [System.Net.WebException] {
        Say "（拿不到校验和文件，跳过校验）"
    }

    Say "解压到 $dest …"
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $dest -Force
    # 清掉"来自 Internet"标记，避免 SmartScreen 拦一下
    Get-ChildItem $dest -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

    $exe = Join-Path $dest "PPTClicker.exe"
    if (-not (Test-Path $exe)) { throw "解压后没找到 PPTClicker.exe" }
    Say "已安装：$exe"

    # 开始菜单快捷方式
    try {
        $lnk = Join-Path (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs") "PPT Clicker.lnk"
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($lnk)
        $shortcut.TargetPath = $exe
        $shortcut.WorkingDirectory = $dest
        $shortcut.Description = "Turn any mouse into a presentation clicker"
        $shortcut.Save()
        Say "已创建开始菜单快捷方式"
    } catch {
        Say "（创建快捷方式失败，可直接运行上面的 exe）"
    }

    Start-Process $exe
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

@"

接下来：
  1. 无需授权，程序已在托盘区运行（右下角），没有任何系统权限要求
  2. 放映 PPT 时，双击鼠标滚轮键开启 —— 屏幕角落的小圆点变绿
  3. 左键 / 滚轮向下 = 下一页   右键 / 滚轮向上 = 上一页
     关闭：按 ESC、再双击滚轮键、或按 Ctrl+Alt+Shift+P

卸载：托盘菜单里取消"开机自动启动"，删掉 $dest 目录即可。
"@ | Write-Host
