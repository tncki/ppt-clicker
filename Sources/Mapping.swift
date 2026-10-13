import CoreGraphics
import Foundation

// MARK: - 动作

/// 一个鼠标事件可以被映射成的动作。
/// pass  = 不拦截，交还给系统（保持原样）
/// none  = 拦截但什么都不做
enum Action: String, Codable, CaseIterable {
    case next
    case prev
    case pageDown
    case pageUp
    case space
    case escape
    case black
    case white
    case none
    case pass

    /// 要合成的虚拟键码（nil 表示不发送任何按键）
    var keyCode: CGKeyCode? {
        switch self {
        case .next: return 124      // →
        case .prev: return 123      // ←
        case .pageDown: return 121  // Page Down
        case .pageUp: return 116    // Page Up
        case .space: return 49
        case .escape: return 53
        case .black: return 11      // b
        case .white: return 13      // w
        case .none, .pass: return nil
        }
    }

    /// 是否吞掉原始鼠标事件
    var shouldSwallow: Bool { self != .pass }

    var postsKey: Bool { keyCode != nil }
}

// MARK: - 鼠标事件种类

enum MouseKind: String, CaseIterable {
    case leftClick
    case rightClick
    case middleClick
    case backButton       // 侧键"后退"
    case forwardButton    // 侧键"前进"
    case scrollUp
    case scrollDown
    case scrollLeft
    case scrollRight

    var label: String {
        switch self {
        case .leftClick: return "左键"
        case .rightClick: return "右键"
        case .middleClick: return "中键"
        case .backButton: return "侧键后退"
        case .forwardButton: return "侧键前进"
        case .scrollUp: return "滚轮上"
        case .scrollDown: return "滚轮下"
        case .scrollLeft: return "滚轮左"
        case .scrollRight: return "滚轮右"
        }
    }
}

// MARK: - 绑定表

struct Bindings: Codable {
    var leftClick: Action = .next
    var rightClick: Action = .prev
    var middleClick: Action = .pass
    var backButton: Action = .pass
    var forwardButton: Action = .pass
    var scrollUp: Action = .prev
    var scrollDown: Action = .next
    var scrollLeft: Action = .pass
    var scrollRight: Action = .pass

    init() {}

    enum CodingKeys: String, CodingKey {
        case leftClick, rightClick, middleClick, backButton, forwardButton
        case scrollUp, scrollDown, scrollLeft, scrollRight
    }

    /// 宽容解析：写错的键或值退回默认值，不会因为一个笔误整份配置失效。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func pick(_ key: CodingKeys, _ fallback: Action) -> Action {
            (try? c.decode(Action.self, forKey: key)) ?? fallback
        }
        leftClick = pick(.leftClick, .next)
        rightClick = pick(.rightClick, .prev)
        middleClick = pick(.middleClick, .pass)
        backButton = pick(.backButton, .pass)
        forwardButton = pick(.forwardButton, .pass)
        scrollUp = pick(.scrollUp, .prev)
        scrollDown = pick(.scrollDown, .next)
        scrollLeft = pick(.scrollLeft, .pass)
        scrollRight = pick(.scrollRight, .pass)
    }

    func action(for kind: MouseKind) -> Action {
        switch kind {
        case .leftClick: return leftClick
        case .rightClick: return rightClick
        case .middleClick: return middleClick
        case .backButton: return backButton
        case .forwardButton: return forwardButton
        case .scrollUp: return scrollUp
        case .scrollDown: return scrollDown
        case .scrollLeft: return scrollLeft
        case .scrollRight: return scrollRight
        }
    }
}

// MARK: - 滚轮节流

/// 一次滚轮/惯性滚动会产生很多事件，必须节流，否则一拨就翻好几页。
struct Throttle {
    private var last: TimeInterval = -1e18

    mutating func allow(now: TimeInterval, interval: TimeInterval) -> Bool {
        if now - last < interval { return false }
        last = now
        return true
    }

    mutating func reset() { last = -1e18 }
}

// MARK: - 应用白名单

struct AppRule: Codable, Equatable {
    var bundleID: String
    var name: String?

    enum CodingKeys: String, CodingKey { case bundleID, name }
}

enum Scope: String, Codable {
    case global   // 只要开关打开，任何软件里都生效
    case apps     // 仅当前台 App 属于 apps 列表时生效
}

// MARK: - 全局热键

struct Hotkey: Codable {
    var key: String = "p"
    var modifiers: [String] = ["control", "option", "command"]

    init() {}

    enum CodingKeys: String, CodingKey { case key, modifiers }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let k = try? c.decode(String.self, forKey: .key), !k.isEmpty, KeyCodeTable.code(for: k) != nil {
            key = k
        }
        if let m = try? c.decode([String].self, forKey: .modifiers) { modifiers = m }
        // 安全兜底：热键至少要带一个修饰键，否则会退化成"裸按某个键"，
        // 全局吞掉普通打字（比如单独吞掉 p）。
        if flagMask.isEmpty { modifiers = ["control", "option", "command"] }
    }

    var keyCode: CGKeyCode? { KeyCodeTable.code(for: key) }

    var flagMask: CGEventFlags {
        var flags: CGEventFlags = []
        for m in modifiers.map({ $0.lowercased() }) {
            switch m {
            case "control", "ctrl": flags.insert(.maskControl)
            case "option", "alt": flags.insert(.maskAlternate)
            case "command", "cmd": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            default: break
            }
        }
        return flags
    }

    var display: String {
        let lower = modifiers.map { $0.lowercased() }
        var s = ""
        if lower.contains("control") { s += "⌃" }
        if lower.contains("option") { s += "⌥" }
        if lower.contains("shift") { s += "⇧" }
        if lower.contains("command") { s += "⌘" }
        return s + key.uppercased()
    }
}

enum KeyCodeTable {
    static let named: [String: CGKeyCode] = {
        var m: [String: CGKeyCode] = [:]
        let letters: [(String, CGKeyCode)] = [
            ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7),
            ("c", 8), ("v", 9), ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15),
            ("y", 16), ("t", 17), ("o", 31), ("u", 32), ("i", 34), ("p", 35), ("l", 37),
            ("j", 38), ("k", 40), ("n", 45), ("m", 46),
        ]
        for (k, v) in letters { m[k] = v }

        let digits: [(String, CGKeyCode)] = [
            ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("5", 23),
            ("6", 22), ("7", 26), ("8", 28), ("9", 25), ("0", 29),
        ]
        for (k, v) in digits { m[k] = v }

        m["space"] = 49
        m["escape"] = 53
        m["esc"] = 53
        m["return"] = 36
        m["enter"] = 36
        m["tab"] = 48
        m["left"] = 123
        m["right"] = 124
        m["down"] = 125
        m["up"] = 126
        m["pageup"] = 116
        m["pagedown"] = 121
        m["home"] = 115
        m["end"] = 119
        m["minus"] = 27
        m["equal"] = 24
        m["comma"] = 43
        m["period"] = 47
        m["slash"] = 44

        let functionKeys: [CGKeyCode] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (i, code) in functionKeys.enumerated() { m["f\(i + 1)"] = code }

        return m
    }()

    static func code(for name: String) -> CGKeyCode? {
        named[name.lowercased()]
    }
}

/// 判断一次 keyDown 是否命中配置的热键（纯函数，方便自测）。
func hotkeyMatches(keyCode: CGKeyCode, flags: CGEventFlags, hotkey: Hotkey) -> Bool {
    guard let wanted = hotkey.keyCode, wanted == keyCode else { return false }
    let relevant: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
    return flags.intersection(relevant) == hotkey.flagMask
}

func isTargetApp(bundleID: String?, rules: [AppRule]) -> Bool {
    guard let id = bundleID else { return false }
    return rules.contains { $0.bundleID.caseInsensitiveCompare(id) == .orderedSame }
}

/// 滚轮方向的语义：桌面鼠标"向下滚"到底对应 axis1 的哪个符号，
/// 取决于系统设置里的「自然滚动」。所以默认交给程序自动判断，
/// 用户也可以手动指定。
enum ScrollDirectionSetting: String, Codable, CaseIterable {
    case auto       // 跟随系统「自然滚动」
    case normal     // 非自然滚动：向下滚 → axis1 < 0
    case inverted   // 自然滚动：向下滚 → axis1 > 0
}

/// 读取系统「自然滚动」开关（NSGlobalDomain 的 com.apple.swipescrolldirection）。
/// macOS 默认开启自然滚动，所以读不到时按开启处理。
func systemNaturalScrolling() -> Bool {
    if let value = UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool {
        return value
    }
    return true
}

/// 解析：物理"向下滚"是否对应 axis1 为正。
func physicalDownIsPositive(_ direction: ScrollDirectionSetting) -> Bool {
    switch direction {
    case .auto: return systemNaturalScrolling()
    case .normal: return false
    case .inverted: return true
    }
}

/// 把滚轮事件的原始 delta 翻译成"物理方向"。
/// downIsPositive = 物理向下滚时 axis1 为正（由 physicalDownIsPositive 解析得到）。
func scrollKind(axis1: Double, axis2: Double, downIsPositive: Bool) -> MouseKind? {
    if abs(axis1) >= abs(axis2), axis1 != 0 {
        let isDown = downIsPositive ? (axis1 > 0) : (axis1 < 0)
        return isDown ? .scrollDown : .scrollUp
    }
    if axis2 != 0 {
        let isRight = downIsPositive ? (axis2 > 0) : (axis2 < 0)
        return isRight ? .scrollRight : .scrollLeft
    }
    return nil
}

/// 双击检测（用于"双击滚轮键切换模式"）。纯逻辑，方便自测。
struct DoubleClickDetector {
    private var lastAt: TimeInterval?
    private var lastTriggerAt: TimeInterval = -1e18

    /// 记录一次按下；返回 true 表示这一下构成了双击。
    /// 触发后会有一段冷却期，避免连按滚轮键被反复当成新的双击。
    mutating func register(now: TimeInterval, interval: TimeInterval) -> Bool {
        if now - lastTriggerAt < interval {
            lastAt = nil
            return false
        }
        if let last = lastAt, now - last <= interval {
            lastAt = nil
            lastTriggerAt = now
            return true
        }
        lastAt = now
        return false
    }

    mutating func reset() {
        lastAt = nil
        lastTriggerAt = -1e18
    }
}
