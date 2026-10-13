import CoreGraphics
import Foundation

/// 无界面自测：验证映射、节流、配置解析、热键匹配等纯逻辑。
/// 运行：PPTClicker --selftest
enum SelfTest {

    private static var passed = 0
    private static var failed = 0

    private static func check(_ condition: Bool, _ name: String) {
        if condition {
            passed += 1
            print("  ✓ \(name)")
        } else {
            failed += 1
            print("  ✗ \(name)")
        }
    }

    static func run() -> Bool {
        print("PPTClicker 自测")

        print("[1] 默认映射")
        let b = Bindings()
        check(b.leftClick == .next, "左键 → 下一页")
        check(b.rightClick == .prev, "右键 → 上一页")
        check(b.scrollDown == .next, "滚轮下 → 下一页")
        check(b.scrollUp == .prev, "滚轮上 → 上一页")
        check(b.middleClick == .pass, "中键 → 放行（默认）")
        check(b.action(for: .leftClick) == .next, "action(for:) 路由正确")

        print("[2] 动作 → 虚拟键码")
        check(Action.next.keyCode == 124, "next → → (124)")
        check(Action.prev.keyCode == 123, "prev → ← (123)")
        check(Action.pageDown.keyCode == 121, "pageDown → 121")
        check(Action.space.keyCode == 49, "space → 49")
        check(Action.black.keyCode == 11, "black → b (11)")
        check(Action.pass.keyCode == nil && Action.pass.shouldSwallow == false, "pass 不发送按键且不拦截")
        check(Action.none.keyCode == nil && Action.none.shouldSwallow, "none 拦截但不发按键")
        check(Action.next.shouldSwallow && Action.next.postsKey, "next 拦截并发送按键")

        print("[3] 滚轮节流")
        var throttle = Throttle()
        check(throttle.allow(now: 100.0, interval: 0.3), "首次触发允许")
        check(!throttle.allow(now: 100.1, interval: 0.3), "30ms 内连发被抑制")
        check(!throttle.allow(now: 100.29, interval: 0.3), "290ms 仍被抑制")
        check(throttle.allow(now: 100.31, interval: 0.3), "超过 300ms 恢复允许")
        throttle.reset()
        check(throttle.allow(now: 100.05, interval: 0.3), "reset 后立即允许")

        print("[4] 默认配置模板解析")
        guard let config = ConfigStore.decode(Config.defaultJSONTemplate) else {
            print("  ✗ 默认模板无法解析")
            failed += 1
            return finish()
        }
        check(config.bindings.leftClick == .next, "模板 leftClick=next")
        check(config.bindings.scrollUp == .prev, "模板 scrollUp=prev")
        check(config.hotkey.key == "p", "模板热键 key=p")
        check(config.hotkey.display == "⌃⌥⌘P", "模板热键显示为 ⌃⌥⌘P（实际 \(config.hotkey.display)）")
        check(config.scope == .global, "模板 scope=global")
        check(config.apps.count >= 5, "模板包含多个演示软件（实际 \(config.apps.count) 个）")
        check(config.throttleMs == 300 && abs(config.throttleInterval - 0.3) < 1e-9, "模板 throttleMs=300")
        check(config.apps.contains { $0.bundleID == "com.apple.iWork.Keynote" }, "包含 Keynote")
        check(config.apps.contains { $0.bundleID == "com.kingsoft.wpsoffice.mac" }, "包含 WPS")
        check(config.apps.contains { $0.bundleID == "org.libreoffice.script" }, "包含 LibreOffice")
        check(config.apps.contains { $0.bundleID == "com.microsoft.Powerpoint" }, "包含 PowerPoint")
        check(config.apps.contains { $0.bundleID == "com.apple.Preview" }, "包含 Preview")

        print("[5] 宽容解析（写错不影响其它项）")
        let partial = """
        { "bindings": { "leftClick": "pass", "scrollDown": "none" },
          "hotkey": { "key": "k", "modifiers": ["command", "shift"] },
          "scope": "apps",
          "未知字段": 123 }
        """
        guard let p = ConfigStore.decode(partial) else {
            print("  ✗ 局部配置无法解析")
            failed += 1
            return finish()
        }
        check(p.bindings.leftClick == .pass, "覆盖 leftClick=pass")
        check(p.bindings.scrollDown == .none, "覆盖 scrollDown=none")
        check(p.bindings.scrollUp == .prev, "未写的 scrollUp 保持默认 prev")
        check(p.bindings.rightClick == .prev, "未写的 rightClick 保持默认 prev")
        check(p.hotkey.keyCode == KeyCodeTable.code(for: "k"), "热键 k 键码正确")
        check(p.hotkey.display == "⇧⌘K", "热键显示 ⇧⌘K（实际 \(p.hotkey.display)）")
        check(p.scope == .apps, "scope=apps")

        print("[6] 非法值回退")
        let bogus = """
        { "bindings": { "leftClick": "这不是动作", "scrollUp": "" },
          "hotkey": { "key": "不存在的键" },
          "throttleMs": -5 }
        """
        guard let g = ConfigStore.decode(bogus) else {
            print("  ✗ 非法配置不应解析失败")
            failed += 1
            return finish()
        }
        check(g.bindings.leftClick == .next, "非法动作回退为默认 next")
        check(g.bindings.scrollUp == .prev, "非法动作回退为默认 prev")
        check(g.hotkey.keyCode == KeyCodeTable.code(for: "p"), "非法热键名回退为 p")
        check(g.throttleMs == 300, "负数 throttleMs 回退为 300")

        print("[6b] 热键安全兜底")
        let noMods = ConfigStore.decode(#"{ "hotkey": { "key": "p", "modifiers": [] } }"#)
        check(noMods?.hotkey.flagMask.isEmpty == false, "空修饰键被强制补回修饰键（避免裸按吞键）")
        check(noMods?.hotkey.display == "⌃⌥⌘P", "空修饰键兜底显示 ⌃⌥⌘P（实际 \(noMods?.hotkey.display ?? "nil")）")
        let shiftOnly = ConfigStore.decode(#"{ "hotkey": { "key": "p", "modifiers": ["shift"] } }"#)
        check(shiftOnly?.hotkey.display == "⇧P", "只写 shift 时保留 ⇧P")

        print("[7] 热键匹配")
        let hotkey = Hotkey()
        let allMods: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        check(hotkeyMatches(keyCode: 35, flags: allMods, hotkey: hotkey), "⌃⌥⌘P 命中")
        check(
            hotkeyMatches(keyCode: 35, flags: allMods.union(.maskNonCoalesced), hotkey: hotkey),
            "带额外标志位仍命中"
        )
        check(!hotkeyMatches(keyCode: 35, flags: [.maskCommand, .maskAlternate], hotkey: hotkey), "少按 ⌃ 不命中")
        check(!hotkeyMatches(keyCode: 35, flags: allMods.union(.maskShift), hotkey: hotkey), "多按 ⇧ 不命中")
        check(!hotkeyMatches(keyCode: 36, flags: allMods, hotkey: hotkey), "按错键不命中")

        print("[8] 演示软件白名单匹配")
        let apps = Config.defaultApps
        check(isTargetApp(bundleID: "com.apple.iWork.Keynote", rules: apps), "Keynote 命中")
        check(isTargetApp(bundleID: "COM.APPLE.IWORK.KEYNOTE", rules: apps), "大小写不敏感")
        check(!isTargetApp(bundleID: "com.apple.finder", rules: apps), "Finder 不命中")
        check(!isTargetApp(bundleID: nil, rules: apps), "无前台 App 不命中")
        check(
            isTargetApp(bundleID: "com.apple.systempreferences", rules: Config.systemExclusions),
            "系统设置属于放行名单"
        )

        print("[9] 配置序列化往返")
        if let json = try? config.jsonString(), let round = ConfigStore.decode(json) {
            check(round.bindings.leftClick == config.bindings.leftClick, "编码后仍能解回 leftClick")
            check(round.hotkey.display == config.hotkey.display, "编码后仍能解回热键")
            check(round.apps.count == config.apps.count, "编码后 App 列表一致")
        } else {
            check(false, "配置序列化往返")
        }

        print("[10] 滚轮/鼠标事件口径")
        check(MouseKind.allCases.count == 9, "共 9 种鼠标事件")
        check(MouseKind.scrollDown.label == "滚轮下" && MouseKind.rightClick.label == "右键", "事件名称正确")

        print("[11] 滚轮方向（自然滚动开启时：向下滚 → axis1 为正）")
        let defaults = Bindings()
        // downIsPositive = 物理向下滚对应 axis1 为正（自然滚动机器的情形）
        check(scrollKind(axis1: 3, axis2: 0, downIsPositive: true) == .scrollDown, "轴1=+3 → 物理向下滚")
        check(scrollKind(axis1: -3, axis2: 0, downIsPositive: true) == .scrollUp, "轴1=-3 → 物理向上滚")
        check(scrollKind(axis1: 1, axis2: 0, downIsPositive: true) == .scrollDown, "轴1=+1 同样是向下")
        // 非自然滚动机器：符号相反，但"物理向下"依然是下一页
        check(scrollKind(axis1: -3, axis2: 0, downIsPositive: false) == .scrollDown, "非自然滚动：轴1=-3 → 物理向下滚")
        check(scrollKind(axis1: 3, axis2: 0, downIsPositive: false) == .scrollUp, "非自然滚动：轴1=+3 → 物理向上滚")
        check(scrollKind(axis1: 0, axis2: -2, downIsPositive: true) == .scrollLeft, "轴2=-2 → 向左滚")
        check(scrollKind(axis1: 0, axis2: 2, downIsPositive: true) == .scrollRight, "轴2=+2 → 向右滚")
        check(scrollKind(axis1: 0, axis2: 0, downIsPositive: true) == nil, "零位移不产生动作")
        check(scrollKind(axis1: 5, axis2: 1, downIsPositive: true) == .scrollDown, "纵向优先于横向")
        // 关键回归：不管系统怎么设置，"物理向下滚"都必须落到"下一页"
        check(defaults.action(for: scrollKind(axis1: 3, axis2: 0, downIsPositive: true)!) == .next, "自然滚动机器：向下滚 → 下一页")
        check(defaults.action(for: scrollKind(axis1: -3, axis2: 0, downIsPositive: false)!) == .next, "非自然滚动机器：向下滚 → 下一页")
        check(defaults.action(for: scrollKind(axis1: -3, axis2: 0, downIsPositive: true)!) == .prev, "自然滚动机器：向上滚 → 上一页")

        print("[11b] 方向自动判定")
        check(physicalDownIsPositive(.normal) == false, "normal：向下滚 axis1 为负")
        check(physicalDownIsPositive(.inverted) == true, "inverted：向下滚 axis1 为正")
        let natural = systemNaturalScrolling()
        check(physicalDownIsPositive(.auto) == natural, "auto 跟随系统自然滚动设置（本机自然滚动=\(natural ? "开" : "关")）")

        print("[12] 双击滚轮键检测")
        var detector = DoubleClickDetector()
        check(!detector.register(now: 100.0, interval: 0.45), "第 1 下不算双击")
        check(detector.register(now: 100.2, interval: 0.45), "200ms 内的第 2 下 = 双击")
        check(!detector.register(now: 100.3, interval: 0.45), "刚触发完，冷却期内不再触发")
        check(!detector.register(now: 100.6, interval: 0.45), "冷却期内连按也只算一次")
        check(!detector.register(now: 101.0, interval: 0.45), "冷却结束后这是新序列的第 1 下")
        check(detector.register(now: 101.2, interval: 0.45), "随后 200ms 内构成新的双击")
        var slow = DoubleClickDetector()
        check(!slow.register(now: 200.0, interval: 0.45), "孤立的第 1 下")
        check(!slow.register(now: 200.9, interval: 0.45), "间隔 900ms 不算双击")
        check(slow.register(now: 201.2, interval: 0.45), "再下一 300ms 内算双击")

        print("[13] 新增开关的默认值与解析")
        let fresh = Config()
        check(fresh.escapeDisables, "默认 ESC 可关闭模式")
        check(fresh.middleDoubleClickToggles, "默认双击滚轮键可切换")
        check(fresh.showIndicator, "默认显示角落指示灯")
        if let parsed = ConfigStore.decode(Config.defaultJSONTemplate) {
            check(parsed.escapeDisables && parsed.middleDoubleClickToggles && parsed.showIndicator, "模板解析出三项新开关")
        } else {
            check(false, "模板解析")
        }
        if let off = ConfigStore.decode(#"{ "escapeDisables": false, "middleDoubleClickToggles": false, "showIndicator": false }"#) {
            check(!off.escapeDisables && !off.middleDoubleClickToggles && !off.showIndicator, "三项都能关闭")
        } else {
            check(false, "新开关解析")
        }

        return finish()
    }

    private static func finish() -> Bool {
        print("")
        print("结果：\(passed) 通过 / \(failed) 失败")
        return failed == 0
    }
}
