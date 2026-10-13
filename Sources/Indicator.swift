import AppKit

/// 小小的状态指示灯：一颗圆点，常驻屏幕角落，浮在所有窗口之上。
/// - 绿灯 = 翻页笔模式开启
/// - 灰圈 = 已关闭
/// 左键点击 = 开关，右键 = 弹出完整菜单，按住拖动 = 换位置。
final class IndicatorView: NSView {

    var isOn = false {
        didSet {
            needsDisplay = true
            if isOn != oldValue { startPulse() }
        }
    }

    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onMoved: ((NSPoint) -> Void)?

    private var pulsing = false
    private var pulseTimer: Timer?

    private var didDrag = false
    private var dragAnchorScreen: NSPoint = .zero
    private var windowAnchor: NSPoint = .zero

    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: 3.5, dy: 3.5)
        let path = NSBezierPath(ovalIn: circle)

        if isOn {
            NSColor.systemGreen.withAlphaComponent(pulsing ? 1.0 : 0.92).setFill()
            path.fill()
            // 外发光，让"已开启"更醒目
            NSColor.systemGreen.withAlphaComponent(pulsing ? 0.55 : 0.30).setStroke()
            path.lineWidth = 2.0
            path.stroke()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            let inner = NSBezierPath(ovalIn: circle.insetBy(dx: 0.5, dy: 0.5))
            inner.lineWidth = 0.5
            inner.stroke()
        } else {
            NSColor(calibratedWhite: 0.55, alpha: 0.22).setFill()
            path.fill()
            NSColor(calibratedWhite: 0.60, alpha: 0.50).setStroke()
            path.lineWidth = 1.0
            path.stroke()
        }
    }

    /// 状态刚变化时闪一下，方便余光看到
    private func startPulse() {
        pulsing = true
        needsDisplay = true
        pulseTimer?.invalidate()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            self?.pulsing = false
            self?.needsDisplay = true
        }
    }

    // MARK: - 点击 / 拖动

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        dragAnchorScreen = NSEvent.mouseLocation
        windowAnchor = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - dragAnchorScreen.x
        let dy = now.y - dragAnchorScreen.y
        if abs(dx) + abs(dy) > 2 { didDrag = true }
        window.setFrameOrigin(NSPoint(x: windowAnchor.x + dx, y: windowAnchor.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag {
            onMoved?(window?.frame.origin ?? .zero)
        } else {
            onClick?()
        }
        didDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }
}

final class IndicatorWindow: NSPanel {

    let indicator = IndicatorView()

    static let dotSize: CGFloat = 16

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.dotSize, height: Self.dotSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        // 跟着出现在所有桌面空间、并且能盖在全屏放映之上
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = indicator
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
