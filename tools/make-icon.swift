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


// MARK: - ICO（Windows 用）

func appendU16(_ data: inout Data, _ value: UInt16) {
    data.append(UInt8(value & 0xFF))
    data.append(UInt8((value >> 8) & 0xFF))
}

func appendU32(_ data: inout Data, _ value: UInt32) {
    data.append(UInt8(value & 0xFF))
    data.append(UInt8((value >> 8) & 0xFF))
    data.append(UInt8((value >> 16) & 0xFF))
    data.append(UInt8((value >> 24) & 0xFF))
}

/// 把图标渲染成 ICO（每个尺寸一条 32 位 BMP + AND 掩码，兼容性最好）
func writeICO(master: NSImage, to url: URL, sizes: [Int]) {
    var entries: [(Int, Data)] = []

    for size in sizes {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32
        ) else { continue }

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.imageInterpolation = .high
            master.draw(
                in: NSRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)),
                from: NSRect(origin: .zero, size: master.size),
                operation: .copy, fraction: 1.0
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let src = rep.bitmapData else { continue }
        let rowBytes = rep.bytesPerRow

        var bmp = Data()
        // BITMAPINFOHEADER（必须正好 40 字节：其中 biPlanes/biBitCount 是 2 字节字段）
        appendU32(&bmp, 40)                    // biSize
        appendU32(&bmp, UInt32(size))          // biWidth
        appendU32(&bmp, UInt32(size * 2))      // biHeight = 图像 + AND 掩码
        appendU16(&bmp, 1)                     // biPlanes
        appendU16(&bmp, 32)                    // biBitCount
        appendU32(&bmp, 0)                     // biCompression
        appendU32(&bmp, 0)                     // biSizeImage
        appendU32(&bmp, 0)                     // biXPelsPerMeter
        appendU32(&bmp, 0)                     // biYPelsPerMeter
        appendU32(&bmp, 0)                     // biClrUsed
        appendU32(&bmp, 0)                     // biClrImportant
        // 像素：BGRA、自下而上；AppKit 是预乘 alpha，这里反预乘
        for y in stride(from: size - 1, through: 0, by: -1) {
            let row = src + y * rowBytes
            for x in 0..<size {
                let p = row + x * 4
                var r = UInt32(p[0]), g = UInt32(p[1]), b = UInt32(p[2])
                let a = UInt32(p[3])
                if a > 0 && a < 255 {
                    r = min(255, r * 255 / a)
                    g = min(255, g * 255 / a)
                    b = min(255, b * 255 / a)
                }
                bmp.append(UInt8(b)); bmp.append(UInt8(g)); bmp.append(UInt8(r)); bmp.append(UInt8(a))
            }
        }
        // AND 掩码：1 表示透明，每行 4 字节对齐
        let maskRowBytes = ((size + 31) / 32) * 4
        for y in stride(from: size - 1, through: 0, by: -1) {
            let row = src + y * rowBytes
            var bits = [UInt8](repeating: 0, count: maskRowBytes)
            for x in 0..<size where row[x * 4 + 3] == 0 {
                bits[x / 8] |= UInt8(0x80 >> (x % 8))
            }
            bmp.append(contentsOf: bits)
        }
        entries.append((size, bmp))
    }

    var out = Data()
    appendU16(&out, 0)                       // reserved
    appendU16(&out, 1)                       // type = icon
    appendU16(&out, UInt16(entries.count))
    var offset = 6 + 16 * entries.count
    for (size, data) in entries {
        out.append(UInt8(size >= 256 ? 0 : size))
        out.append(UInt8(size >= 256 ? 0 : size))
        out.append(0)                        // 调色板数
        out.append(0)                        // reserved
        appendU16(&out, 1)                   // planes
        appendU16(&out, 32)                  // bpp
        appendU32(&out, UInt32(data.count))
        appendU32(&out, UInt32(offset))
        offset += data.count
    }
    for (_, data) in entries { out.append(data) }

    try? out.write(to: url)
    print("wrote \(url.lastPathComponent) (\(entries.count) 个尺寸, \(out.count) 字节)")
}

let master = drawIcon(size: 1024)

let variants: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

if outputDir.hasSuffix(".ico") {
    writeICO(master: master, to: URL(fileURLWithPath: outputDir), sizes: [16, 24, 32, 48, 64, 128, 256])
    exit(0)
}

let dir = URL(fileURLWithPath: outputDir)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for (name, size) in variants {
    write(master, size: size, to: dir.appendingPathComponent(name))
    print("wrote \(name) (\(Int(size))px)")
}
