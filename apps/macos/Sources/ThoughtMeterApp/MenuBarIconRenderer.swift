import AppKit

/// Draws the ThoughtMeter menu bar mark: a small gauge (arc + needle + hub).
/// Rendered programmatically as a template image so it adapts to light/dark
/// menu bars. Each tracking state gets a distinct, glanceable variant.
enum MenuBarIconRenderer {
    private static var cache: [String: NSImage] = [:]

    static func image(for state: MenuBarIconState) -> NSImage {
        let key = String(describing: state)
        if let cached = cache[key] { return cached }
        let image = draw(state: state)
        cache[key] = image
        return image
    }

    private static func draw(state: MenuBarIconState) -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY - 2.5)
            let radius: CGFloat = 6.5

            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 190, endAngle: -10, clockwise: true)
            arc.lineWidth = 1.6
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()

            switch state {
            case .active, .chromeDisconnected, .noPermission:
                let angle: CGFloat = state == .noPermission ? 170 : 55
                let radians = angle * .pi / 180
                let tip = NSPoint(x: center.x + cos(radians) * (radius - 1.5),
                                  y: center.y + sin(radians) * (radius - 1.5))
                let needle = NSBezierPath()
                needle.move(to: center)
                needle.line(to: tip)
                needle.lineWidth = 1.6
                needle.lineCapStyle = .round
                needle.stroke()
            case .paused:
                for xOffset in [-2.2, 1.0] {
                    let bar = NSBezierPath(
                        roundedRect: NSRect(x: center.x + xOffset, y: center.y - 0.5, width: 1.4, height: 5.5),
                        xRadius: 0.7, yRadius: 0.7
                    )
                    NSColor.black.setFill()
                    bar.fill()
                }
            }

            let hub = NSBezierPath(ovalIn: NSRect(x: center.x - 1.4, y: center.y - 1.4, width: 2.8, height: 2.8))
            NSColor.black.setFill()
            hub.fill()

            switch state {
            case .noPermission:
                let stem = NSBezierPath(roundedRect: NSRect(x: rect.maxX - 3.4, y: 4.5, width: 1.6, height: 5),
                                        xRadius: 0.8, yRadius: 0.8)
                stem.fill()
                let dot = NSBezierPath(ovalIn: NSRect(x: rect.maxX - 3.4, y: 1.6, width: 1.6, height: 1.6))
                dot.fill()
            case .chromeDisconnected:
                let badge = NSBezierPath(ovalIn: NSRect(x: rect.maxX - 5, y: 1.2, width: 4, height: 4))
                badge.lineWidth = 1.1
                badge.stroke()
            case .active, .paused:
                break
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
