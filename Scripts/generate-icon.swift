#!/usr/bin/env swift
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]

func generateIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext

    // Background - dark rounded rect
    let cornerRadius = s * 0.22
    let bgRect = NSRect(x: 0, y: 0, width: s, height: s)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Gradient background: dark blue to dark purple
    let gradient = NSGradient(colors: [
        NSColor(red: 0.10, green: 0.10, blue: 0.18, alpha: 1.0),
        NSColor(red: 0.15, green: 0.08, blue: 0.22, alpha: 1.0),
    ])!
    gradient.draw(in: bgPath, angle: -45)

    // "AFK" text
    let fontSize = s * 0.32
    let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let text = "AFK"
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let textSize = text.size(withAttributes: attrs)
    let textX = (s - textSize.width) / 2
    let textY = (s - textSize.height) / 2 - s * 0.02
    text.draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)

    // Small green dot (status indicator) - top right area
    let dotSize = s * 0.14
    let dotX = s * 0.72
    let dotY = s * 0.68
    let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)

    // Glow
    let glowColor = NSColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 0.3)
    glowColor.setFill()
    let glowRect = dotRect.insetBy(dx: -s * 0.03, dy: -s * 0.03)
    NSBezierPath(ovalIn: glowRect).fill()

    // Dot
    let dotColor = NSColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1.0)
    dotColor.setFill()
    NSBezierPath(ovalIn: dotRect).fill()

    image.unlockFocus()
    return image
}

// Generate iconset
let iconsetPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/AFK.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let iconSizes = [16, 32, 128, 256, 512]
for size in iconSizes {
    // 1x
    let img1x = generateIcon(size: size)
    let rep1x = NSBitmapImageRep(data: img1x.tiffRepresentation!)!
    rep1x.size = NSSize(width: size, height: size)
    let png1x = rep1x.representation(using: .png, properties: [:])!
    try! png1x.write(to: URL(fileURLWithPath: "\(iconsetPath)/icon_\(size)x\(size).png"))

    // 2x
    let img2x = generateIcon(size: size * 2)
    let rep2x = NSBitmapImageRep(data: img2x.tiffRepresentation!)!
    rep2x.size = NSSize(width: size, height: size)
    let png2x = rep2x.representation(using: .png, properties: [:])!
    try! png2x.write(to: URL(fileURLWithPath: "\(iconsetPath)/icon_\(size)x\(size)@2x.png"))
}

print("Iconset generated at: \(iconsetPath)")
