import AppKit
import Foundation

let arguments = CommandLine.arguments

if arguments.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
}

if arguments.contains("--print-default-config") {
    print(Config.defaultJSONTemplate)
    exit(0)
}

if arguments.contains("--print-effective-config") {
    // 只读：不会创建配置文件
    let config = ConfigStore.load(createIfMissing: false)
    print((try? config.jsonString()) ?? "{}")
    exit(0)
}

// 隐藏用例：改配置文件里的诊断开关（供无人值守排查用）
// 用法：open -a PPTClicker.app --args --debug-events on|off
if let index = arguments.firstIndex(of: "--debug-events"), index + 1 < arguments.count {
    let value = arguments[index + 1].lowercased()
    var config = ConfigStore.load()
    config.debugEvents = (value == "on" || value == "true" || value == "1")
    let ok = ConfigStore.save(config)
    print("debugEvents = \(config.debugEvents)，写入\(ok ? "成功" : "失败")：\(ConfigStore.url.path)")
    exit(ok ? 0 : 1)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
