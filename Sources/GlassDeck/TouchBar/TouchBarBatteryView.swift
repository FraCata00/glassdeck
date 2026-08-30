import AppKit
import GlassDeckKit

/// The compact battery chip for the Touch Bar: system glyph plus percentage.
///
/// It stays deliberately small — the point is to save room for the graphs — and
/// turns green while charging, which is the one state worth spotting at a glance.
final class TouchBarBatteryView: NSView {
    var battery: BatteryUsage = .unavailable {
        didSet {
            guard battery != oldValue else { return }
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 62, height: 30) }
    override var allowsVibrancy: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(dirtyRect)

        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 7, yRadius: 7)
        NSColor.white.withAlphaComponent(0.08).setFill()
        background.fill()

        let tint: NSColor = battery.isCharging
            ? .systemGreen
            : (battery.fraction <= 0.15 && !battery.isPluggedIn ? .systemRed : .white)

        let bodyRect = NSRect(x: 7, y: (bounds.height - 9).rounded() / 2, width: 17, height: 9)
        drawBattery(in: bodyRect, tint: tint)
        drawPercentage(after: bodyRect.maxX + 5, tint: tint)
    }

    /// Draws the battery the way the menu bar does: a thin shell, a level that
    /// fills it, and a bolt while charging. Hand-drawing beats the SF Symbol here
    /// because the level has to be readable at a glance, not just the outline.
    private func drawBattery(in rect: NSRect, tint: NSColor) {
        let shell = NSBezierPath(roundedRect: rect, xRadius: 2.6, yRadius: 2.6)
        shell.lineWidth = 0.9
        tint.withAlphaComponent(0.55).setStroke()
        shell.stroke()

        // The terminal nub on the right-hand side.
        let nub = NSBezierPath(
            roundedRect: NSRect(x: rect.maxX + 1.2, y: rect.midY - 1.9, width: 1.6, height: 3.8),
            xRadius: 0.8,
            yRadius: 0.8
        )
        tint.withAlphaComponent(0.55).setFill()
        nub.fill()

        guard battery.isAvailable else {
            // A single stroke through the shell marks "no battery".
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: rect.minX + 2, y: rect.minY + 2))
            slash.line(to: NSPoint(x: rect.maxX - 2, y: rect.maxY - 2))
            slash.lineWidth = 1.2
            tint.withAlphaComponent(0.7).setStroke()
            slash.stroke()
            return
        }

        let inset = rect.insetBy(dx: 1.6, dy: 1.6)
        let level = NSRect(
            x: inset.minX,
            y: inset.minY,
            width: max(1.2, inset.width * CGFloat(battery.fraction)),
            height: inset.height
        )
        tint.setFill()
        NSBezierPath(roundedRect: level, xRadius: 1.3, yRadius: 1.3).fill()

        guard battery.isCharging else { return }
        drawBolt(in: rect)
    }

    /// A small lightning bolt punched out of the level so it stays visible
    /// whatever the charge is.
    private func drawBolt(in rect: NSRect) {
        let bolt = NSBezierPath()
        let centre = NSPoint(x: rect.midX, y: rect.midY)
        bolt.move(to: NSPoint(x: centre.x + 1.2, y: centre.y + 3.4))
        bolt.line(to: NSPoint(x: centre.x - 1.8, y: centre.y + 0.1))
        bolt.line(to: NSPoint(x: centre.x + 0.1, y: centre.y + 0.1))
        bolt.line(to: NSPoint(x: centre.x - 1.2, y: centre.y - 3.4))
        bolt.line(to: NSPoint(x: centre.x + 1.8, y: centre.y - 0.1))
        bolt.line(to: NSPoint(x: centre.x - 0.1, y: centre.y - 0.1))
        bolt.close()

        NSColor.black.withAlphaComponent(0.85).setFill()
        bolt.fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        bolt.lineWidth = 0.5
        bolt.stroke()
    }

    private func drawPercentage(after x: CGFloat, tint: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        NSAttributedString(
            string: battery.isAvailable ? "\(battery.percentage)%" : "–",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: tint,
                .paragraphStyle: paragraph,
            ]
        ).draw(in: NSRect(x: x, y: 8, width: bounds.width - x - 6, height: 15))
    }
}
