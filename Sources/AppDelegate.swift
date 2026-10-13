import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let tap = EventTapController()
    private var config = Config()
    private var refreshTimer: Timer?
    private var menuSignature = ""
    private var ticks = 0
    private var installFailures = 0

    private var enabled = false
    private var scopeOverride: Scope?

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var hotkeyRegistered = false
    private var lastToggleAt: TimeInterval = -1e18

    private var indicator: IndicatorWindow?
    private var escMonitor: Any?
    private var builtMenu: NSMenu?

    private static let indicatorOriginKey = "indicatorOrigin"
    private static let indicatorVisibleKey = "indicatorVisible"

    private var indicatorVisible: Bool {
        if UserDefaults.standard.object(forKey: Self.indicatorVisibleKey) != nil {
            return UserDefaults.standard.bool(forKey: Self.indicatorVisibleKey)
        }
        return config.showIndicator
    }

    private let scopeDefaultsKey = "scopeOverride"

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        exitIfAlreadyRunning()

        if let saved = UserDefaults.standard.string(forKey: scopeDefaultsKey), let s = Scope(rawValue: saved) {
            scopeOverride = s
        }

        config = ConfigStore.load()
        enabled = config.startEnabled
        applyConfig(config)

        Log.shared.configure(enabled: config.debugLog, path: config.logPath)
        Log.shared.write("启动 PPT Clicker \(Self.appVersion)（config: \(ConfigStore.url.path)）")
        let natural = systemNaturalScrolling()
        let downIsPositive = physicalDownIsPositive(config.scrollDirection)
        Log.shared.write("滚轮方向：系统自然滚动=\(natural ? "开启" : "关闭")，设置=\(config.scrollDirection.rawValue) → 物理向下滚 axis1 \(downIsPositive ? "为正" : "为负")")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.toolTip = "PPT 翻页笔"

        tap.onToggleRequest = { [weak self] in self?.toggleMode() }
        tap.onEscapeRequest = { [weak self] in self?.escapePressed(source: "事件监听") }

        // 顺序很重要：先注册系统全局快捷键，这样事件监听就不用监听键盘，
        // 也就不需要"输入监控"权限了。
        registerGlobalHotkey()
        requestPermissions()
        tryInstallTap()
        setupIndicator()
        installEscapeMonitor()
        refreshMenu(force: true)
        logStatusItemDiagnostics("启动后")
        showFirstRunGuideIfNeeded()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.ticks += 1
            if !self.tap.isInstalled { self.tryInstallTap() }
            self.updateStatusRect()
            self.refreshMenu()
            self.updateIndicator()
            // 启动后依次做通道自检，并把状态栏项状态写进日志
            if self.ticks == 2 {
                self.logStatusItemDiagnostics("第 \(self.ticks) 次心跳")
                self.runKeyboardSelfTest()
            }
            if self.ticks == 10 { self.logStatusItemDiagnostics("第 \(self.ticks) 次心跳") }
        }
    }

    /// 状态栏图标到底有没有真的画出来、在哪块屏上——排查"看不到图标"类问题用。
    private func logStatusItemDiagnostics(_ tag: String) {
        var parts: [String] = ["诊断[\(tag)]"]
        parts.append("itemIsVisible=\(statusItem?.isVisible ?? false)")
        parts.append("hastButton=\(statusItem?.button != nil)")
        parts.append("hasImage=\(statusItem?.button?.image != nil)")
        parts.append("imageSize=\(String(describing: statusItem?.button?.image?.size))")
        parts.append("title=\(statusItem?.button?.title ?? "nil")")
        parts.append("hotkeyRegistered=\(hotkeyRegistered)")
        if let window = statusItem?.button?.window {
            parts.append("windowFrame=\(window.frame)")
            parts.append("windowVisible=\(window.isVisible)")
            parts.append("windowScreen=\(window.screen?.localizedName ?? "nil")")
            parts.append("windowScreenFrame=\(String(describing: window.screen?.frame))")
        } else {
            parts.append("window=nil")
        }
        parts.append("screens=\(NSScreen.screens.map { NSStringFromRect($0.frame) })")
        parts.append("menuBarThickness=\(NSStatusBar.system.thickness)")
        if let indicator {
            parts.append("indicatorVisible=\(indicator.isVisible)")
            parts.append("indicatorFrame=\(indicator.frame)")
            parts.append("indicatorOn=\(indicator.indicator.isOn)")
        } else {
            parts.append("indicator=nil")
        }
        Log.shared.write(parts.joined(separator: " "))
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        unregisterGlobalHotkey()
        tap.uninstall()
        Log.shared.write("退出")
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    /// 首次启动（或该版本首次启动）时的引导
    private func showFirstRunGuideIfNeeded() {
        let key = "guideShownVersion"
        guard UserDefaults.standard.string(forKey: key) != Self.appVersion else { return }
        UserDefaults.standard.set(Self.appVersion, forKey: key)
        // 已经授权过就不打扰
        guard !accessibilityGranted else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, !self.accessibilityGranted else { return }
            let alert = NSAlert()
            alert.messageText = L.s("欢迎使用 PPT 翻页笔")
            alert.informativeText = L.isChinese
                ? """
                三步就能用：

                1. 点下面的按钮，在「辅助功能」里把 PPT Clicker 打开（拦截鼠标必需）
                2. 双击鼠标滚轮键 → 屏幕右上角的小圆点变绿，就是已开启
                3. 左键 / 滚轮向下 = 下一页，右键 / 滚轮向上 = 上一页

                关闭：再双击滚轮键、按 ESC、或再按一次快捷键 \(self.config.hotkey.display)
                """
                : """
                Three steps:

                1. Click the button below and enable PPT Clicker in Accessibility (required to intercept the mouse)
                2. Double-click the mouse wheel button -> the dot in the top-right corner turns green
                3. Left click / wheel down = next slide, right click / wheel up = previous slide

                Turn off: double-click the wheel again, press ESC, or press \(self.config.hotkey.display) again
                """
            alert.addButton(withTitle: L.s("打开系统设置授权"))
            alert.addButton(withTitle: L.s("稍后"))
            if alert.runModal() == .alertFirstButtonReturn {
                self.openAccessibilitySettings()
            }
        }
    }

    private func exitIfAlreadyRunning() {
        let id = Bundle.main.bundleIdentifier ?? "ai.dsh.pptclicker"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != getpid() }
        if !others.isEmpty {
            Log.shared.write("已有实例在运行（pid \(others.map { $0.processIdentifier })），本次退出")
            exit(0)
        }
    }

    private func applyConfig(_ config: Config) {
        let neededKeysBefore = tap.wantsKeyEvents
        tap.bindings = config.bindings
        tap.throttleInterval = config.throttleInterval
        tap.targetApps = config.apps
        tap.excludeApps = config.excludeApps
        tap.hotkey = config.hotkey
        tap.scope = effectiveScope(config)
        tap.isEnabled = enabled
        tap.debugEvents = config.debugEvents
        tap.verboseLogging = config.debugEvents
        tap.scrollDownIsPositive = physicalDownIsPositive(config.scrollDirection)
        tap.escapeDisables = config.escapeDisables
        tap.middleDoubleClickToggles = config.middleDoubleClickToggles
        // 订阅的事件类型变了就得重建事件监听
        if tap.isInstalled, neededKeysBefore != tap.wantsKeyEvents {
            tap.uninstall()
            tryInstallTap()
        }
    }

    // MARK: - 角落指示灯

    private func setupIndicator() {
        guard indicatorVisible else {
            indicator?.orderOut(nil)
            return
        }
        if indicator == nil {
            let window = IndicatorWindow()
            window.indicator.onClick = { [weak self] in
                Log.shared.write("点击指示灯 → 切换模式")
                self?.toggleMode()
            }
            window.indicator.onRightClick = { [weak self] event in
                self?.showMenuPopUp(event)
            }
            window.indicator.onMoved = { origin in
                UserDefaults.standard.set(NSStringFromPoint(origin), forKey: Self.indicatorOriginKey)
            }
            indicator = window
        }
        positionIndicatorIfNeeded()
        indicator?.indicator.isOn = enabled
        indicator?.orderFrontRegardless()
    }

    private func updateIndicator() {
        guard indicatorVisible else {
            indicator?.orderOut(nil)
            return
        }
        if indicator == nil { setupIndicator() }
        indicator?.indicator.isOn = enabled
    }

    private func positionIndicatorIfNeeded() {
        guard let window = indicator else { return }
        let size = window.frame.size
        if let saved = UserDefaults.standard.string(forKey: Self.indicatorOriginKey) {
            let origin = NSPointFromString(saved)
            if NSScreen.screens.contains(where: { $0.frame.intersects(NSRect(origin: origin, size: size)) }) {
                window.setFrameOrigin(origin)
                return
            }
        }
        window.setFrameOrigin(defaultIndicatorOrigin(size: size))
    }

    /// 默认位置：内置屏顶部靠右、贴着菜单栏下沿的角落
    private func defaultIndicatorOrigin(size: NSSize) -> NSPoint {
        guard let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            return NSPoint(x: 40, y: 40)
        }
        return NSPoint(x: visible.maxX - size.width - 10, y: visible.maxY - size.height - 8)
    }

    private func showMenuPopUp(_ event: NSEvent) {
        guard let menu = builtMenu, let view = event.window?.contentView else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func toggleIndicator() {
        let next = !indicatorVisible
        UserDefaults.standard.set(next, forKey: Self.indicatorVisibleKey)
        if next { setupIndicator() } else { indicator?.orderOut(nil) }
        Log.shared.write("角落指示灯：\(next ? "显示" : "隐藏")")
        refreshMenu(force: true)
    }

    // MARK: - ESC 关闭（旁听，不拦截）

    private func installEscapeMonitor() {
        guard config.escapeDisables else {
            if let escMonitor { NSEvent.removeMonitor(escMonitor) }
            escMonitor = nil
            return
        }
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            // 只看 ESC 一个键，其它按键不做任何记录
            guard event.keyCode == 53 else { return }
            DispatchQueue.main.async { self?.escapePressed(source: "全局监听") }
        }
        if escMonitor == nil {
            Log.shared.write("ESC 监听安装失败：需要『输入监控』权限，ESC 将无法关闭翻页笔模式")
        } else {
            Log.shared.write("ESC 监听已安装（只旁听 ESC，不拦截按键，放映仍可用 ESC 结束）")
        }
    }

    private func escapePressed(source: String) {
        guard enabled else { return }
        setEnabled(false, reason: "ESC/\(source)")
    }

    private var effectiveScope: Scope { scopeOverride ?? config.scope }

    private func effectiveScope(_ config: Config) -> Scope { scopeOverride ?? config.scope }

    // MARK: - 权限

    private var accessibilityGranted: Bool { AXIsProcessTrusted() }

    private var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }

    private func requestPermissions() {
        if !accessibilityGranted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            Log.shared.write("缺少辅助功能权限，已弹出系统授权引导（拦截鼠标唯一必需的权限）")
        } else {
            Log.shared.write("辅助功能权限：已授权")
        }

        // 只有全局快捷键注册失败、退回到"从事件链里拦按键"时才需要输入监控
        if tap.useTapHotkey {
            if !inputMonitoringGranted {
                _ = CGRequestListenEventAccess()
                Log.shared.write("全局快捷键未注册成功，需要输入监控权限作为兜底")
            } else {
                Log.shared.write("输入监控权限：已授权（兜底需要）")
            }
        } else if config.escapeDisables, !inputMonitoringGranted {
            // ESC 关闭功能要"旁听"按键
            _ = CGRequestListenEventAccess()
            Log.shared.write("ESC 关闭功能需要『输入监控』权限，已弹出授权引导（不给也能用快捷键/双击滚轮关闭）")
        }
    }

    private func tryInstallTap() {
        guard !tap.isInstalled else { return }
        updateStatusRect()
        if tap.install() {
            installFailures = 0
            Log.shared.write("事件监听已安装（辅助功能 \(accessibilityGranted ? "OK" : "缺失")，输入监控 \(inputMonitoringGranted ? "OK" : "缺失")）")
            // 装好之后自动验证一次鼠标通道
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.runMouseSelfTest()
            }
        } else {
            installFailures += 1
            // 只在第一次和每 20 次失败时报一次，避免日志被刷爆
            if installFailures == 1 || installFailures % 20 == 0 {
                Log.shared.write("事件监听安装失败（第 \(installFailures) 次）：通常是还没授予『辅助功能』或『输入监控』权限")
            }
        }
    }

    // MARK: - 菜单

    private func refreshMenu(force: Bool = false) {
        updateStatusRect()
        let signature = [
            enabled ? "1" : "0",
            effectiveScope.rawValue,
            accessibilityGranted ? "1" : "0",
            inputMonitoringGranted ? "1" : "0",
            tap.isInstalled ? "1" : "0",
            loginItemInstalled() ? "1" : "0",
            String(tap.interceptedCount),
            tap.debugEvents ? "1" : "0",
            hotkeyRegistered ? "1" : "0",
            indicatorVisible ? "1" : "0",
        ].joined(separator: "|")

        updateIcon()

        // 菜单正开着就别重建它
        if tap.bypassInterception && !force { return }

        guard force || signature != menuSignature else { return }
        menuSignature = signature
        buildMenu()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let working = tap.isInstalled
        // 注意：无论权限是否齐全，都必须如实显示开关状态，
        // 否则会出现"按了快捷键但图标没反应"的假象。
        let enabledImage = enabled ? "play.rectangle.fill" : "pause.rectangle"
        let name = working ? enabledImage : "exclamationmark.triangle"
        let title: String
        if enabled {
            title = working ? "翻页中" : "翻页中!"
        } else {
            title = working ? "翻页笔" : "翻页笔!"
        }

        let image = NSImage(systemSymbolName: name, accessibilityDescription: "PPT 翻页笔")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.title = title

        if !working {
            button.toolTip = L.s(enabled ? "PPT 翻页笔：已开启" : "PPT 翻页笔：已关闭") + L.s("；但事件监听未生效，请授予『辅助功能』权限") + "（\(config.hotkey.display)" + L.s("（切换）") + ")"
        } else {
            button.toolTip = L.s(enabled ? "PPT 翻页笔：已开启" : "PPT 翻页笔：已关闭") + "（\(config.hotkey.display)" + L.s("（切换）") + ")"
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(
            title: L.s(enabled ? "翻页笔模式：已开启" : "翻页笔模式：已关闭"),
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        let toggle = NSMenuItem(
            title: "\(L.s("切换翻页笔模式"))（\(config.hotkey.display)）",
            action: #selector(toggleMode),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.state = enabled ? .on : .off
        menu.addItem(toggle)

        let closeHint = NSMenuItem(
            title: L.s("关闭方式：再按一次快捷键 ・ ESC\(config.escapeDisables ? "" : "（已关）") ・ 双击滚轮键\(config.middleDoubleClickToggles ? "" : "（已关）")"),
            action: nil,
            keyEquivalent: ""
        )
        closeHint.isEnabled = false
        menu.addItem(closeHint)

        menu.addItem(.separator())

        let scopeItem = NSMenuItem(
            title: L.s("仅在前台是演示软件时生效"),
            action: #selector(toggleScope),
            keyEquivalent: ""
        )
        scopeItem.target = self
        scopeItem.state = effectiveScope == .apps ? .on : .off
        menu.addItem(scopeItem)

        let indicatorItem = NSMenuItem(
            title: L.s("显示屏幕角落的指示灯"),
            action: #selector(toggleIndicator),
            keyEquivalent: ""
        )
        indicatorItem.target = self
        indicatorItem.state = indicatorVisible ? .on : .off
        menu.addItem(indicatorItem)

        let mapping = NSMenuItem(
            title: L.s("当前映射：") + "L:\(label(config.bindings.leftClick))" + L.s("，滚轮下→") + label(config.bindings.scrollDown) + L.s("，右键→") + label(config.bindings.rightClick) + L.s("，滚轮上→") + label(config.bindings.scrollUp),
            action: nil,
            keyEquivalent: ""
        )
        mapping.isEnabled = false
        menu.addItem(mapping)

        menu.addItem(.separator())

        let reload = NSMenuItem(title: L.s("重新载入配置"), action: #selector(reloadConfig), keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)

        let openConfig = NSMenuItem(title: L.s("打开配置文件…"), action: #selector(openConfigFile), keyEquivalent: "")
        openConfig.target = self
        menu.addItem(openConfig)

        let openLog = NSMenuItem(title: L.s("打开日志…"), action: #selector(openLogFile), keyEquivalent: "")
        openLog.target = self
        menu.addItem(openLog)

        menu.addItem(.separator())

        let tapItem = NSMenuItem(title: L.s(tap.isInstalled ? "事件监听：正常" : "事件监听：未安装"), action: nil, keyEquivalent: "")
        tapItem.isEnabled = false
        menu.addItem(tapItem)

        let hotkeyItem = NSMenuItem(
            title: "\(L.s("全局快捷键")) \(config.hotkey.display)：" + L.s(hotkeyRegistered ? "已注册" : "未注册（改用事件监听兜底）"),
            action: nil,
            keyEquivalent: ""
        )
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)

        let axItem = NSMenuItem(
            title: L.s(accessibilityGranted ? "辅助功能权限：已授权" : "辅助功能权限：未授权 —— 点此去开启"),
            action: accessibilityGranted ? nil : #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        axItem.target = self
        menu.addItem(axItem)

        if tap.useTapHotkey {
            let imItem = NSMenuItem(
                title: L.s(inputMonitoringGranted ? "输入监控权限：已授权" : "输入监控权限：未授权 —— 点此去开启"),
                action: inputMonitoringGranted ? nil : #selector(openInputMonitoringSettings),
                keyEquivalent: ""
            )
            imItem.target = self
            menu.addItem(imItem)
        }

        let countItem = NSMenuItem(title: L.s("已拦截事件：") + "\(tap.interceptedCount)", action: nil, keyEquivalent: "")
        countItem.isEnabled = false
        menu.addItem(countItem)

        let diagItem = NSMenuItem(
            title: L.s("记录原始事件到日志（诊断用）"),
            action: #selector(toggleEventDebug),
            keyEquivalent: ""
        )
        diagItem.target = self
        diagItem.state = tap.debugEvents ? .on : .off
        menu.addItem(diagItem)

        let dumpItem = NSMenuItem(title: L.s("把状态栏诊断写进日志"), action: #selector(dumpDiagnostics), keyEquivalent: "")
        dumpItem.target = self
        menu.addItem(dumpItem)

        menu.addItem(.separator())

        let login = NSMenuItem(title: L.s("开机自动启动"), action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = loginItemInstalled() ? .on : .off
        menu.addItem(login)

        let quit = NSMenuItem(title: L.s("退出"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        builtMenu = menu
        menu.delegate = self
    }

    // MARK: - 菜单开关期间暂停拦截

    func menuWillOpen(_ menu: NSMenu) {
        tap.bypassInterception = true
        updateStatusRect()
    }

    func menuDidClose(_ menu: NSMenu) {
        tap.bypassInterception = false
    }

    @objc private func toggleEventDebug() {
        tap.debugEvents.toggle()
        Log.shared.write("原始事件诊断日志：\(tap.debugEvents ? "开启" : "关闭")")
        refreshMenu(force: true)
    }

    @objc private func dumpDiagnostics() {
        logStatusItemDiagnostics("手动")
        runKeyboardSelfTest()
        runMouseSelfTest()
        refreshMenu(force: true)
    }

    /// 自动验证全局按键通道是否真的通：合成一次热键，看能不能被自己收到。
    private func runKeyboardSelfTest() {
        guard tap.isInstalled, tap.useTapHotkey else { return }
        let ok = tap.runKeyboardSelfTest()
        Log.shared.write("键盘事件通道自检：\(ok ? "通过——能收到全局按键" : "失败——收不到按键，请检查『输入监控』权限")")
    }

    /// 自动验证 HID 鼠标通道是否真的通：合成一次会被自己吞掉的点击。
    /// 落点选菜单栏图标正中间：万一监听没生效，最坏结果也只是打开本程序自己的菜单。
    private func runMouseSelfTest() {
        guard tap.isInstalled else {
            Log.shared.write("鼠标通道自检：跳过（事件监听未安装）")
            return
        }
        updateStatusRect()
        guard let rect = tap.statusItemRect, rect.width > 1 else {
            Log.shared.write("鼠标通道自检：跳过（状态栏图标位置未知）")
            return
        }
        let ok = tap.runMouseSelfTest(at: CGPoint(x: rect.midX, y: rect.midY))
        Log.shared.write("鼠标通道自检：\(ok ? "通过——能拦到 HID 鼠标事件" : "失败——收不到鼠标事件")")
    }

    // MARK: - 全局快捷键（Carbon RegisterEventHotKey，不需要任何权限）

    private func registerGlobalHotkey() {
        unregisterGlobalHotkey()
        guard let keyCode = config.hotkey.keyCode else {
            Log.shared.write("全局快捷键注册失败：按键名无法识别（\(config.hotkey.key)）")
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { delegate.toggleMode() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandlerRef
        )
        guard installStatus == noErr else {
            Log.shared.write("全局快捷键注册失败：InstallEventHandler 返回 \(installStatus)")
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x5050_5443), id: 1)  // 'PPTC'
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers(config.hotkey.flagMask),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        // 注册成功：事件链里不再重复处理这个按键，避免切换两次
        hotkeyRegistered = (status == noErr)
        tap.useTapHotkey = !hotkeyRegistered
        if hotkeyRegistered {
            Log.shared.write("全局快捷键已注册：\(config.hotkey.display)")
        } else {
            Log.shared.write("全局快捷键注册失败（错误码 \(status)，可能已被其它 App 占用），回退到事件监听方式处理按键")
        }
    }

    private func unregisterGlobalHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
            self.hotKeyHandlerRef = nil
        }
        hotkeyRegistered = false
    }

    private func carbonModifiers(_ flags: CGEventFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.maskCommand) { mods |= UInt32(cmdKey) }
        if flags.contains(.maskAlternate) { mods |= UInt32(optionKey) }
        if flags.contains(.maskControl) { mods |= UInt32(controlKey) }
        if flags.contains(.maskShift) { mods |= UInt32(shiftKey) }
        return mods
    }

    private func label(_ action: Action) -> String {
        switch action {
        case .next: return L.s("下一页 →")
        case .prev: return L.s("上一页 ←")
        case .pass: return L.s("保持原样")
        case .none: return L.s("拦截但无动作")
        default: return action.rawValue
        }
    }

    private func updateStatusRect() {
        guard let window = statusItem?.button?.window else {
            tap.statusItemRect = nil
            return
        }
        let frame = window.frame
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        tap.statusItemRect = CGRect(
            x: frame.minX,
            y: screenHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    // MARK: - 动作

    @objc private func toggleMode() {
        // 防抖：连按或按键重复时不要来回抖动
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastToggleAt < 0.35 { return }
        lastToggleAt = now
        setEnabled(!enabled, reason: "快捷键")
    }

    /// 统一的开关入口（快捷键 / ESC / 双击滚轮 / 点指示灯 / 菜单 都走这里）
    private func setEnabled(_ value: Bool, reason: String) {
        guard value != enabled else { return }
        enabled = value
        tap.isEnabled = value
        tap.resetPending()
        Log.shared.write("翻页笔模式：\(value ? "开启" : "关闭")（来自\(reason)）")
        if value && !tap.isInstalled { tryInstallTap() }
        refreshMenu(force: true)
        updateIndicator()
    }

    @objc private func toggleScope() {
        scopeOverride = effectiveScope == .apps ? .global : .apps
        UserDefaults.standard.set(scopeOverride?.rawValue, forKey: scopeDefaultsKey)
        tap.scope = effectiveScope
        Log.shared.write("生效范围：\(effectiveScope == .apps ? "仅演示软件" : "全局")")
        refreshMenu(force: true)
    }

    @objc private func reloadConfig() {
        config = ConfigStore.load()
        applyConfig(config)
        Log.shared.configure(enabled: config.debugLog, path: config.logPath)
        registerGlobalHotkey()
        setupIndicator()
        installEscapeMonitor()
        Log.shared.write("已重新载入配置：\(ConfigStore.url.path)")
        refreshMenu(force: true)
    }

    @objc private func openConfigFile() {
        let url = ConfigStore.ensureConfigFile()
        NSWorkspace.shared.open(url)
    }

    @objc private func openLogFile() {
        let path = Log.shared.currentPath
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func openAccessibilitySettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @objc private func openInputMonitoringSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - 开机自启（LaunchAgent）

    private static let launchAgentLabel = "io.github.pptclicker"

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.launchAgentLabel).plist")
    }

    private func loginItemInstalled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    @objc private func toggleLoginItem() {
        if loginItemInstalled() {
            uninstallLoginItem()
        } else {
            installLoginItem()
        }
        refreshMenu(force: true)
    }

    private func installLoginItem() {
        let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let plist: [String: Any] = [
            "Label": Self.launchAgentLabel,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        do {
            try FileManager.default.createDirectory(
                at: launchAgentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: launchAgentURL)
            runLaunchctl(["bootstrap", "gui/\(getuid())", launchAgentURL.path])
            Log.shared.write("已安装开机自启：\(launchAgentURL.path)")
        } catch {
            Log.shared.write("安装开机自启失败：\(error)")
        }
    }

    private func uninstallLoginItem() {
        runLaunchctl(["bootout", "gui/\(getuid())", launchAgentURL.path])
        try? FileManager.default.removeItem(at: launchAgentURL)
        Log.shared.write("已移除开机自启")
    }

    private func runLaunchctl(_ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
