import CoreGraphics
import Foundation

// 诊断小工具：列出指定 pid 拥有的窗口（层级 / 位置 / 尺寸）
// 用法：winlist <pid>
let args = CommandLine.arguments
guard args.count > 1, let pid = Int(args[1]) else {
    print("用法: winlist <pid>")
    exit(2)
}

guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
    print("无法获取窗口列表")
    exit(1)
}

var found = 0
for w in list {
    guard let owner = w[kCGWindowOwnerPID as String] as? Int, owner == pid else { continue }
    found += 1
    let layer = w[kCGWindowLayer as String] as? Int ?? -1
    let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let name = w[kCGWindowName as String] as? String ?? "(名字需屏幕录制权限)"
    let onScreen = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
    let x = bounds["X"] as? Double ?? -1
    let y = bounds["Y"] as? Double ?? -1
    let width = bounds["Width"] as? Double ?? -1
    let height = bounds["Height"] as? Double ?? -1
    print("layer=\(layer) onscreen=\(onScreen) rect=(\(Int(x)),\(Int(y)) \(Int(width))x\(Int(height))) name=\(name)")
}
print("pid \(pid) 共 \(found) 个窗口")
