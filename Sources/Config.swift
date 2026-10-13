import Foundation

struct Config: Codable {
    var bindings: Bindings = Bindings()
    var scope: Scope = .global
    var apps: [AppRule] = Config.defaultApps
    var excludeApps: [AppRule] = Config.systemExclusions
    var hotkey: Hotkey = Hotkey()
    var throttleMs: Int = 300
    var debugLog: Bool = true
    /// 诊断用：把收到的每一个按键/鼠标原始事件写进日志（排查问题时才开）
    var debugEvents: Bool = false
    /// 滚轮方向：auto 跟随系统「自然滚动」，normal/inverted 可手动指定
    var scrollDirection: ScrollDirectionSetting = .auto
    /// 按 ESC 也关闭翻页笔模式（只旁听，不拦截，放映仍能正常退出）
    var escapeDisables: Bool = true
    /// 双击滚轮键（中键）切换模式
    var middleDoubleClickToggles: Bool = true
    /// 桌面角落的状态指示灯
    var showIndicator: Bool = true
    var logPath: String = Config.defaultLogPath
    var startEnabled: Bool = false

    /// 默认日志位置（标准 macOS 位置，不再是 /tmp）
    static let defaultLogPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/PPTClicker.log").path

    static let defaultApps: [AppRule] = [
        AppRule(bundleID: "com.apple.iWork.Keynote", name: "Keynote"),
        AppRule(bundleID: "com.microsoft.Powerpoint", name: "Microsoft PowerPoint"),
        AppRule(bundleID: "com.kingsoft.wpsoffice.mac", name: "WPS Office"),
        AppRule(bundleID: "org.libreoffice.script", name: "LibreOffice Impress"),
        AppRule(bundleID: "com.apple.Preview", name: "Preview"),
        AppRule(bundleID: "com.adobe.Acrobat.Pro", name: "Adobe Acrobat"),
        AppRule(bundleID: "com.google.Chrome", name: "Google Chrome"),
        AppRule(bundleID: "com.apple.Safari", name: "Safari"),
        AppRule(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge"),
    ]

    /// 这些 App 里的点击永远放行（否则系统弹窗、权限设置页会点不动）。
    static let systemExclusions: [AppRule] = [
        AppRule(bundleID: "com.apple.systempreferences", name: "系统设置"),
        AppRule(bundleID: "com.apple.SystemSettings", name: "系统设置"),
        AppRule(bundleID: "com.apple.UserNotificationCenter", name: nil),
        AppRule(bundleID: "com.apple.CoreServicesUIAgent", name: nil),
        AppRule(bundleID: "com.apple.SecurityAgent", name: nil),
        AppRule(bundleID: "com.apple.loginwindow", name: nil),
    ]

    init() {}

    enum CodingKeys: String, CodingKey {
        case bindings, scope, apps, excludeApps, hotkey
        case throttleMs, debugLog, debugEvents, scrollDirection, logPath, startEnabled
        case escapeDisables, middleDoubleClickToggles, showIndicator
    }

    /// 仅用于读取已废弃的旧字段
    private enum LegacyCodingKeys: String, CodingKey { case invertScroll }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bindings = (try? c.decode(Bindings.self, forKey: .bindings)) ?? Bindings()
        if let s = try? c.decode(Scope.self, forKey: .scope) { scope = s }
        if let a = try? c.decode([AppRule].self, forKey: .apps), !a.isEmpty { apps = a }
        if let e = try? c.decode([AppRule].self, forKey: .excludeApps), !e.isEmpty { excludeApps = e }
        if let h = try? c.decode(Hotkey.self, forKey: .hotkey) { hotkey = h }
        if let t = try? c.decode(Int.self, forKey: .throttleMs), t >= 0 { throttleMs = t }
        if let d = try? c.decode(Bool.self, forKey: .debugLog) { debugLog = d }
        if let d = try? c.decode(Bool.self, forKey: .debugEvents) { debugEvents = d }
        if let d = try? c.decode(ScrollDirectionSetting.self, forKey: .scrollDirection) { scrollDirection = d }
        // 兼容旧版字段 invertScroll：false 表示跟随本机自然滚动，true 表示相反
        if (try? c.decode(ScrollDirectionSetting.self, forKey: .scrollDirection)) == nil {
            // 旧版字段 invertScroll（注意它不在 CodingKeys 里，否则编解码合成会失败）
            let legacyKeys = try? decoder.container(keyedBy: LegacyCodingKeys.self)
            if let legacy = try? legacyKeys?.decode(Bool.self, forKey: .invertScroll) {
                scrollDirection = (legacy == true) ? .normal : .inverted
            }
        }
        if let d = try? c.decode(Bool.self, forKey: .escapeDisables) { escapeDisables = d }
        if let d = try? c.decode(Bool.self, forKey: .middleDoubleClickToggles) { middleDoubleClickToggles = d }
        if let d = try? c.decode(Bool.self, forKey: .showIndicator) { showIndicator = d }
        if let p = try? c.decode(String.self, forKey: .logPath), !p.isEmpty { logPath = p }
        if let s = try? c.decode(Bool.self, forKey: .startEnabled) { startEnabled = s }
    }

    func jsonString(sorted: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = sorted ? [.prettyPrinted, .sortedKeys] : [.prettyPrinted]
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    var throttleInterval: TimeInterval { Double(throttleMs) / 1000.0 }

    // MARK: 默认配置模板（带 `_` 开头的说明字段，解析时会被忽略）

    static let defaultJSONTemplate = """
    {
      "_说明": "PPT 翻页笔配置。改完在菜单栏点『重新载入配置』，或重启本程序即可生效。",
      "_动作可选值": {
        "next": "下一页（发送 → 键）",
        "prev": "上一页（发送 ← 键）",
        "pageDown": "Page Down",
        "pageUp": "Page Up",
        "space": "空格",
        "escape": "Esc（WPS/Impress 放映中退出；Keynote 无效果）",
        "black": "黑屏（b 键）",
        "white": "白屏（w 键）",
        "none": "拦截这个鼠标事件但什么都不做",
        "pass": "不拦截，保持系统原本行为"
      },
      "_生效时机": "翻页笔模式由快捷键手动开/关；scope=global 表示开启后在所有软件里都生效，scope=apps 表示仅当前台 App 在 apps 列表里时才生效（菜单里也能切）。",
      "_滚轮方向": "auto = 跟随系统『自然滚动』设置自动判断（推荐，换机器也不用改）；若方向仍感觉相反，改成 normal 或 inverted。",
      "scrollDirection": "auto",
      "_关闭方式": "开启用快捷键；关闭可以用 快捷键再按一次 / ESC / 双击滚轮键（中键）。ESC 是旁听不拦截，所以 PPT 自己的『按 ESC 结束放映』照样有效。",
      "escapeDisables": true,
      "middleDoubleClickToggles": true,
      "_指示灯": "屏幕角落的小圆点：绿灯=已开启，灰圈=已关闭。左键点一下=开关，右键=菜单，拖动=换位置（位置会记住）。",
      "showIndicator": true,
      "scope": "global",
      "bindings": {
        "leftClick": "next",
        "rightClick": "prev",
        "middleClick": "pass",
        "backButton": "pass",
        "forwardButton": "pass",
        "scrollUp": "prev",
        "scrollDown": "next",
        "scrollLeft": "pass",
        "scrollRight": "pass"
      },
      "hotkey": {
        "key": "p",
        "modifiers": ["control", "option", "command"]
      },
      "throttleMs": 300,
      "debugLog": true,
      "debugEvents": false,
      "logPath": "~/Library/Logs/PPTClicker.log",
      "startEnabled": false,
      "_apps说明": "只在 scope=apps 时生效。浏览器那三条是给网页版演示（如 Google Slides）用的，如果你担心在浏览器里误触发，删掉即可。",
      "apps": [
        { "bundleID": "com.apple.iWork.Keynote", "name": "Keynote" },
        { "bundleID": "com.microsoft.Powerpoint", "name": "Microsoft PowerPoint" },
        { "bundleID": "com.kingsoft.wpsoffice.mac", "name": "WPS Office" },
        { "bundleID": "org.libreoffice.script", "name": "LibreOffice Impress" },
        { "bundleID": "com.apple.Preview", "name": "Preview" },
        { "bundleID": "com.adobe.Acrobat.Pro", "name": "Adobe Acrobat" },
        { "bundleID": "com.google.Chrome", "name": "Google Chrome" },
        { "bundleID": "com.apple.Safari", "name": "Safari" },
        { "bundleID": "com.microsoft.edgemac", "name": "Microsoft Edge" }
      ],
      "excludeApps": [
        { "bundleID": "com.apple.systempreferences", "name": "系统设置" },
        { "bundleID": "com.apple.UserNotificationCenter" },
        { "bundleID": "com.apple.CoreServicesUIAgent" }
      ]
    }
    """
}

enum ConfigStore {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PPTClicker", isDirectory: true)
    }

    static var defaultURL: URL { directory.appendingPathComponent("config.json") }

    /// 支持用环境变量 PPTCLICKER_CONFIG 指定配置文件位置（便于测试）。
    static var url: URL {
        if let p = ProcessInfo.processInfo.environment["PPTCLICKER_CONFIG"], !p.isEmpty {
            return URL(fileURLWithPath: p)
        }
        return defaultURL
    }

    @discardableResult
    static func load(createIfMissing: Bool = true) -> Config {
        let target = url
        if !FileManager.default.fileExists(atPath: target.path) {
            if createIfMissing { try? writeTemplate(to: target) }
            return decode(Config.defaultJSONTemplate) ?? Config()
        }
        guard let data = try? Data(contentsOf: target),
              let text = String(data: data, encoding: .utf8) else {
            Log.shared.write("配置文件读取失败，使用内置默认值：\(target.path)")
            return decode(Config.defaultJSONTemplate) ?? Config()
        }
        if let config = decode(text) { return config }
        Log.shared.write("配置文件解析失败，使用内置默认值：\(target.path)")
        return decode(Config.defaultJSONTemplate) ?? Config()
    }

    static func decode(_ text: String) -> Config? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    static func writeTemplate(to target: URL) throws {
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Config.defaultJSONTemplate.write(to: target, atomically: true, encoding: .utf8)
    }

    static func ensureConfigFile() -> URL {
        let target = url
        if !FileManager.default.fileExists(atPath: target.path) {
            try? writeTemplate(to: target)
        }
        return target
    }

    /// 保存配置（会丢掉模板里的 `_` 说明字段，属正常现象）
    @discardableResult
    static func save(_ config: Config) -> Bool {
        do {
            let target = url
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try config.jsonString().write(to: target, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
