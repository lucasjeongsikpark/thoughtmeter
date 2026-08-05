#!/usr/bin/env swift
// Generates the ThoughtMeter product mark as PNGs:
//   - apps/macos/Resources/AppIcon.iconset/*  (run iconutil afterwards)
//   - extensions/chrome/assets/icon{16,32,48,128}.png
//
// The mark: a gauge arc with a needle — a meter for human input.
// Drawn programmatically; no third-party art. Run: swift scripts/gen-icons.swift

import AppKit

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func drawMark(size: CGFloat, forAppIcon: Bool) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let scale = size / 128.0

        if forAppIcon {
            // Rounded-square card. macOS icon grid: content inset ~10%.
            let inset = rect.insetBy(dx: size * 0.09, dy: size * 0.09)
            let card = NSBezierPath(roundedRect: inset, xRadius: size * 0.2, yRadius: size * 0.2)
            NSColor(calibratedRed: 0.965, green: 0.958, blue: 0.94, alpha: 1).setFill()
            card.fill()
            NSColor(calibratedWhite: 0, alpha: 0.08).setStroke()
            card.lineWidth = max(1, scale)
            card.stroke()
        }

        let ink = forAppIcon
            ? NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.14, alpha: 1)
            : NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)
        let accent = NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.15, alpha: 1)

        let center = NSPoint(x: rect.midX, y: rect.midY - 10 * scale)
        let radius = 34 * scale
        let stroke = 9 * scale

        // Gauge arc, 200° sweep open at the bottom.
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 190, endAngle: -10, clockwise: true)
        arc.lineWidth = stroke
        arc.lineCapStyle = .round
        ink.setStroke()
        arc.stroke()

        // Needle at 55°, in the accent color.
        let angle: CGFloat = 55 * .pi / 180
        let tip = NSPoint(x: center.x + cos(angle) * (radius - 4 * scale),
                          y: center.y + sin(angle) * (radius - 4 * scale))
        let needle = NSBezierPath()
        needle.move(to: center)
        needle.line(to: tip)
        needle.lineWidth = stroke * 0.9
        needle.lineCapStyle = .round
        accent.setStroke()
        needle.stroke()

        // Hub.
        let hubRadius = 8 * scale
        let hub = NSBezierPath(ovalIn: NSRect(x: center.x - hubRadius, y: center.y - hubRadius,
                                              width: hubRadius * 2, height: hubRadius * 2))
        ink.setFill()
        hub.fill()
        return true
    }
}

func pngData(_ image: NSImage, pixels: Int) -> Data? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
               from: .zero, operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

func write(_ data: Data?, to relativePath: String) {
    guard let data else { fatalError("failed to render \(relativePath)") }
    let url = repoRoot.appendingPathComponent(relativePath)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    try! data.write(to: url)
    print("wrote \(relativePath)")
}

// macOS iconset (name → pixels).
let iconsetEntries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, pixels) in iconsetEntries {
    let image = drawMark(size: CGFloat(pixels), forAppIcon: true)
    write(pngData(image, pixels: pixels), to: "apps/macos/Resources/AppIcon.iconset/\(name)")
}

// Chrome extension icons (transparent background, mark only).
for pixels in [16, 32, 48, 128] {
    let image = drawMark(size: CGFloat(pixels), forAppIcon: false)
    write(pngData(image, pixels: pixels), to: "extensions/chrome/assets/icon\(pixels).png")
}

print("done — now run: iconutil -c icns apps/macos/Resources/AppIcon.iconset -o apps/macos/Resources/AppIcon.icns")
