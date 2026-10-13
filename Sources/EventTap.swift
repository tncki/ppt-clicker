import AppKit
import CoreGraphics
import Foundation

/// 在 HID 层拦截鼠标（和热键）事件，按配置换成按键。
final class EventTapController {

    /// 给本程序自己合成的按键打标记，避免被自己的 tap 再处理一次。
    static let magic: Int64 = 0x5050_5443  // "PPTC"

    /// 自检事件标记：用来验证"按键事件到底能不能被本程序收到"
    static let testTag: Int64 = 0x5054_4354  // "PTCT"

    /// 鼠标自检标记：合成一次会被自己吞掉的点击，验证 HID 鼠标通道
    static let mouseTestTag: Int64 = 0x4D54_4354  // "MTCT"

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private(set) var isInstalled = false
    private(set) var interceptedCount = 0
    private(set) var lastDisabledReason: String?

    var bindings = Bindings()
    var throttleInterval: TimeInterval = 0.3
    var scope: Scope = .global
    var targetApps: [AppRule] = []
    var excludeApps: [AppRule] = []

    var hotkey = Hotkey()
    var isEnabled = false

    /// 诊断用：把收到的原始事件写进日志（默认关闭）
    var debugEvents = false

    /// 物理"向下滚"是否对应 axis1 为正（由 Config.scrollDirection 解析得到）
    var scrollDownIsPositive = true

    /// 是否记录每一次拦截（debugEvents 打开时才记，默认只记生命周期事件）
    var verboseLogging = false

    /// 菜单打开期间暂停拦截，否则点不动自己的菜单项
    var bypassInterception = false

    /// 系统全局快捷键（Carbon）注册成功后，就不要再从事件链里重复处理按键，
    /// 否则一次按键会被切换两次（等于没切换）。
    var useTapHotkey = true

    /// 按 ESC 关闭模式（旁听，不吞事件）
    var escapeDisables = false

    /// 双击滚轮键（中键）切换模式
    var middleDoubleClickToggles = false
    var doubleClickInterval: TimeInterval = 0.45

    /// 需要收到按键事件（任一功能需要就得订阅 keyDown）
    var wantsKeyEvents: Bool { useTapHotkey || escapeDisables }

    /// 菜单栏图标所在屏幕区域（CG 坐标，左上原点）：点这里永远放行，否则自己点不动菜单。
    var statusItemRect: CGRect?

    var onToggleRequest: (() -> Void)?
    var onEscapeRequest: (() -> Void)?

    private var pendingLeftUp = false
    private var pendingRightUp = false
    private var pendingOtherUp = false
    private var scrollThrottle = Throttle()
    private var lastScrollKind: MouseKind?
    private var middleClickDetector = DoubleClickDetector()

    // MARK: - 安装 / 卸载

    @discardableResult
    func install() -> Bool {
        guard !isInstalled else { return true }

        // 只用鼠标事件时，事件监听完全不碰键盘：
        // 既不需要"输入监控"权限，也不会有任何键盘输入进入本程序。
        var mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)
        if useTapHotkey {
            mask |= (1 << CGEventType.keyDown.rawValue)
        }
        if escapeDisables {
            mask |= (1 << CGEventType.keyDown.rawValue)
        }

        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
                return controller.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return false
        }

        tap = port
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        isInstalled = true
        lastDisabledReason = nil
        return true
    }

    func uninstall() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isInstalled = false
    }

    func resetPending() {
        pendingLeftUp = false
        pendingRightUp = false
        pendingOtherUp = false
        scrollThrottle.reset()
    }

    // MARK: - 自检：按键通道能不能收到事件

    private(set) var selfTestKeyObserved = false
    private(set) var selfTestMouseObserved = false

    /// 合成一次带自检标记的左键按下/抬起，看 tap 能不能收到（收到就吞掉，不影响任何 App）。
    /// 位置默认放在菜单栏图标上：万一 tap 没生效，最坏结果也只是打开了本程序自己的菜单。
    func runMouseSelfTest(at point: CGPoint?) -> Bool {
        guard isInstalled, let source = CGEventSource(stateID: .hidSystemState) else { return false }
        guard let location = point ?? statusItemRect.map({ CGPoint(x: $0.midX, y: $0.midY) }) else {
            return false
        }

        selfTestMouseObserved = false
        for isDown in [true, false] {
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: isDown ? .leftMouseDown : .leftMouseUp,
                mouseCursorPosition: location,
                mouseButton: .left
            ) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: Self.mouseTestTag)
            event.post(tap: .cghidEventTap)
        }

        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline && !selfTestMouseObserved {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return selfTestMouseObserved
    }

    /// 合成一次"配置里的热键"按键（带自检标记），看 tap 能不能收到。
    /// 收到说明全局按键通道正常；收不到说明『输入监控』权限或事件链有问题。
    func runKeyboardSelfTest() -> Bool {
        guard isInstalled else { return false }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }

        selfTestKeyObserved = false
        let code = hotkey.keyCode ?? 35
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown) else { continue }
            event.flags = hotkey.flagMask
            event.setIntegerValueField(.eventSourceUserData, value: Self.testTag)
            event.post(tap: .cghidEventTap)
        }

        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline && !selfTestKeyObserved {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return selfTestKeyObserved
    }

    // MARK: - 事件处理

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 系统偶尔会主动关掉 tap，必须自己打开，否则工具会"静默失效"。
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lastDisabledReason = type == .tapDisabledByTimeout ? "timeout" : "userInput"
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.shared.write("事件监听被系统暂停（\(lastDisabledReason ?? "?")），已自动恢复")
            return Unmanaged.passUnretained(event)
        }

        // 放过自己合成的事件
        if event.getIntegerValueField(.eventSourceUserData) == Self.eventSourceTag {
            return Unmanaged.passUnretained(event)
        }

        // 自检事件：只记录"收到了"，不触发任何动作
        if event.getIntegerValueField(.eventSourceUserData) == Self.testTag {
            selfTestKeyObserved = true
            return nil
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.mouseTestTag {
            selfTestMouseObserved = true
            return nil
        }

        if debugEvents { logRaw(type: type, event: event) }

        if type == .keyDown {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if !isRepeat {
                // ESC：只旁听，原事件照常放行（放映仍可用 ESC 结束）
                if escapeDisables, code == 53 {
                    DispatchQueue.main.async { [weak self] in self?.onEscapeRequest?() }
                    return Unmanaged.passUnretained(event)
                }
                if useTapHotkey, hotkeyMatches(keyCode: code, flags: event.flags, hotkey: hotkey) {
                    DispatchQueue.main.async { [weak self] in self?.onToggleRequest?() }
                    return nil
                }
            }
            return Unmanaged.passUnretained(event)
        }

        // 自己的菜单打开时不拦截，否则菜单点不动
        if bypassInterception { return Unmanaged.passUnretained(event) }

        // 双击滚轮键切换模式：必须在"模式是否开启"之前判断，否则关着的时候没法用它开启
        if middleDoubleClickToggles, type == .otherMouseDown,
           event.getIntegerValueField(.mouseEventButtonNumber) == 2 {
            let now = ProcessInfo.processInfo.systemUptime
            if middleClickDetector.register(now: now, interval: doubleClickInterval) {
                Log.shared.write("滚轮键双击 → 切换模式")
                DispatchQueue.main.async { [weak self] in self?.onToggleRequest?() }
                return nil
            }
        }

        // 菜单栏图标区域永远放行
        if let rect = statusItemRect, rect.contains(event.location) {
            return Unmanaged.passUnretained(event)
        }

        guard isEnabled else {
            resetPending()
            return Unmanaged.passUnretained(event)
        }

        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            if isTargetApp(bundleID: front, rules: excludeApps) {
                return Unmanaged.passUnretained(event)
            }
            if scope == .apps, !isTargetApp(bundleID: front, rules: targetApps) {
                return Unmanaged.passUnretained(event)
            }
        }

        switch type {
        case .leftMouseDown:
            return handleButtonDown(.leftClick, event: event) { self.pendingLeftUp = true }
        case .leftMouseUp:
            if pendingLeftUp { pendingLeftUp = false; return nil }
            return Unmanaged.passUnretained(event)

        case .rightMouseDown:
            return handleButtonDown(.rightClick, event: event) { self.pendingRightUp = true }
        case .rightMouseUp:
            if pendingRightUp { pendingRightUp = false; return nil }
            return Unmanaged.passUnretained(event)

        case .otherMouseDown:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            let kind: MouseKind
            switch button {
            case 2: kind = .middleClick
            case 3: kind = .backButton
            case 4: kind = .forwardButton
            default: return Unmanaged.passUnretained(event)
            }
            return handleButtonDown(kind, event: event) { self.pendingOtherUp = true }
        case .otherMouseUp:
            if pendingOtherUp { pendingOtherUp = false; return nil }
            return Unmanaged.passUnretained(event)

        case .scrollWheel:
            return handleScroll(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleButtonDown(
        _ kind: MouseKind,
        event: CGEvent,
        markPending: () -> Void
    ) -> Unmanaged<CGEvent>? {
        let action = bindings.action(for: kind)
        guard action.shouldSwallow else { return Unmanaged.passUnretained(event) }
        markPending()
        perform(action, label: kind.label)
        return nil
    }

    private func handleScroll(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0

        let d1 = axisDelta(1, event: event, continuous: continuous)
        let d2 = axisDelta(2, event: event, continuous: continuous)

        // 惯性滚动阶段只吞掉、不翻页：否则一次拨动会连翻好几页。
        let isInertia = momentum != 0 || (continuous && phase != 0 && phase != 1)
        guard !isInertia else { return nil }

        let kind = scrollKind(axis1: d1, axis2: d2, downIsPositive: scrollDownIsPositive)

        guard let kind else { return nil }
        let action = bindings.action(for: kind)
        guard action.shouldSwallow else { return Unmanaged.passUnretained(event) }

        let now = ProcessInfo.processInfo.systemUptime
        // 方向一变就立刻放行，这样"下一下、上一下"能马上来回翻，不被节流吃掉
        if kind != lastScrollKind {
            scrollThrottle.reset()
            lastScrollKind = kind
        }
        if scrollThrottle.allow(now: now, interval: throttleInterval) {
            let raw = abs(d1) >= abs(d2) ? d1 : d2
            perform(action, label: "滚轮(axis=\(raw > 0 ? "+" : "")\(Int(raw)))")
        }
        return nil
    }

    // MARK: - 诊断日志

    private func logRaw(type: CGEventType, event: CGEvent) {
        switch type {
        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat)
            Log.shared.write("RAW keyDown keyCode=\(code) flags=0x\(String(event.flags.rawValue, radix: 16)) repeat=\(isRepeat)")
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            let loc = event.location
            Log.shared.write("RAW \(Self.name(of: type)) button=\(button) loc=\(Int(loc.x)),\(Int(loc.y))")
        case .scrollWheel:
            Log.shared.write(
                "RAW scroll axis1=\(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))"
                + " point1=\(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))"
                + " axis2=\(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))"
                + " momentum=\(event.getIntegerValueField(.scrollWheelEventMomentumPhase))"
                + " phase=\(event.getIntegerValueField(.scrollWheelEventScrollPhase))"
                + " continuous=\(event.getIntegerValueField(.scrollWheelEventIsContinuous))"
                + " inverted=\(NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice ?? false)"
            )
        default:
            break
        }
    }

    static func name(of type: CGEventType) -> String {
        switch type {
        case .keyDown: return "keyDown"
        case .keyUp: return "keyUp"
        case .leftMouseDown: return "leftDown"
        case .leftMouseUp: return "leftUp"
        case .rightMouseDown: return "rightDown"
        case .rightMouseUp: return "rightUp"
        case .otherMouseDown: return "otherDown"
        case .otherMouseUp: return "otherUp"
        case .scrollWheel: return "scroll"
        default: return "type(\(type.rawValue))"
        }
    }

    private func axisDelta(_ axis: Int, event: CGEvent, continuous: Bool) -> Double {
        if continuous {
            let point = event.getIntegerValueField(
                axis == 1 ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventPointDeltaAxis2
            )
            if point != 0 { return Double(point) }
        }
        let line = event.getIntegerValueField(
            axis == 1 ? .scrollWheelEventDeltaAxis1 : .scrollWheelEventDeltaAxis2
        )
        if line != 0 { return Double(line) }
        return event.getDoubleValueField(
            axis == 1 ? .scrollWheelEventFixedPtDeltaAxis1 : .scrollWheelEventFixedPtDeltaAxis2
        )
    }

    // MARK: - 动作执行

    private func perform(_ action: Action, label: String) {
        interceptedCount += 1
        // 前几次拦截即使在非诊断模式下也记一笔：出了问题日志里至少有证据
        let logIt = verboseLogging || interceptedCount <= 5
        switch action {
        case .pass:
            return
        case .none:
            if logIt { Log.shared.write("\(label) → none（已拦截，无动作）") }
        default:
            guard let code = action.keyCode else { return }
            postKey(code)
            if logIt { Log.shared.write("\(label) → \(action.rawValue)（keyCode \(code)）") }
        }
    }

    private func postKey(_ code: CGKeyCode) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for isDown in [true, false] {
            guard let key = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown) else { continue }
            key.flags = []
            key.setIntegerValueField(.eventSourceUserData, value: Self.eventSourceTag)
            key.post(tap: .cghidEventTap)
        }
    }

    /// 复用 magic 值作为来源标记。
    static var eventSourceTag: Int64 { magic }
}
