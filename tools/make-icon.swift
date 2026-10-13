import AppKit
import Foundation

// 生成 App 图标：一只鼠标 + 一个向右的箭头，输出 iconset 后交给 iconutil。
// 用法：make-icon <输出目录.iconset>

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.iconset"

func drawIcon(size S: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: S, height: S))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    // 背景：圆角矩形 + 竖向渐变
    let inset = S * 0.045
    let rect = NSRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
    let radius = rect.width * 0.225
    let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    ctx.saveGState()
    bg.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.32, alpha: 1),
        NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.14, alpha: 1),
    ])!
    gradient.draw(in: rect, angle: -90)
    ctx.restoreGState()

    // 内描边
    NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
    bg.lineWidth = max(1, S * 0.006)
    bg.stroke()

    // 鼠标主体
    let bodyW = S * 0.30
    let bodyH = S * 0.46
    let bodyX = S * 0.17
    let bodyY = (S - bodyH) / 2
    let body = NSBezierPath(
        roundedRect: NSRect(x: bodyX, y: bodyY, width: bodyW, height: bodyH),
        xRadius: bodyW * 0.42,
        yRadius: bodyW * 0.42
    )
    NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
    body.fill()

    // 滚轮
    let wheelW = bodyW * 0.16
    let wheelH = bodyH * 0.20
    let wheel = NSBezierPath(
        roundedRect: NSRect(
            x: bodyX + (bodyW - wheelW) / 2,
            y: bodyY + bodyH - wheelH - bodyH * 0.16,
            width: wheelW,
            height: wheelH
        ),
        xRadius: wheelW / 2,
        yRadius: wheelW / 2
    )
    NSColor(calibratedRed: 0.42, green: 0.47, blue: 0.55, alpha: 1).setFill()
    wheel.fill()

    // 向右的绿色箭头
    let arrowY = S * 0.5
    let barH = S * 0.075
    let barX = bodyX + bodyW + S * 0.045
    let headW = S * 0.115
    let barW = S * 0.155
    let bar = NSBezierPath(
        roundedRect: NSRect(x: barX, y: arrowY - barH / 2, width: barW, height: barH),
        xRadius: barH / 2,
        yRadius: barH / 2
    )
    NSColor(calibratedRed: 0.21, green: 0.78, blue: 0.35, alpha: 1).setFill()
    bar.fill()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: barX + barW - S * 0.005, y: arrowY + S * 0.095))
    head.line(to: NSPoint(x: barX + barW + headW, y: arrowY))
    head.line(to: NSPoint(x: barX + barW - S * 0.005, y: arrowY - S * 0.095))
    head.close()
    head.fill()

    return image
}

func write(_ image: NSImage, size: CGFloat, to url: URL) {
    let target = NSSize(width: size, height: size)
    let resized = NSImage(size: target)
    resized.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(origin: .zero, size: target),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy,
               fraction: 1.0)
    resized.unlockFocus()

    guard let tiff = resized.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: url)
}

let master = drawIcon(size: 1024)

let variants: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

let dir = URL(fileURLWithPath: outputDir)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for (name, size) in variants {
    write(master, size: size, to: dir.appendingPathComponent(name))
    print("wrote \(name) (\(Int(size))px)")
}
