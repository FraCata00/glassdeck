import AppKit
import GlassDeckKit

/// The compact battery chip for the Touch Bar: system glyph plus percentage.
///
/// It stays deliberately small — the point is to save room for the graphs — and
/// turns green while charging, which is the one state worth spotting at a glance.
/// Plugged in but not charging — the moment before the adapter has negotiated,
/// or a charge held back by the system — shows a plug, so connecting the cable
/// is acknowledged at once either way.
final class TouchBarBatteryView: NSView {
    var battery: BatteryUsage = .unavailable {
        didSet {
            guard battery != oldValue else { return }
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 62, height: 30) }

    /// Tapping the chip expands the battery's own bar, where the power draw lives.
    var onTap: (() -> Void)?

    override func touchesBegan(with event: NSEvent) {
        super.touchesBegan(with: event)
        onTap?()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onTap?()
    }
    override var allowsVibrancy: Bool { true }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { MetricKind.battery.title }
    override func accessibilityValue() -> Any? { battery.headline }
    override func accessibilityHelp() -> String? { battery.caption }

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

        if battery.isCharging {
            drawBolt(in: rect)
        } else if battery.isPluggedIn {
            drawPlug(in: rect)
        }
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

        punchOut(bolt)
    }

    /// A small mains plug, prongs to the right, punched out the same way as the bolt.
    private func drawPlug(in rect: NSRect) {
        let centre = NSPoint(x: rect.midX, y: rect.midY)
        let plug = NSBezierPath(
            roundedRect: NSRect(x: centre.x - 2.6, y: centre.y - 2.3, width: 3.4, height: 4.6),
            xRadius: 1,
            yRadius: 1
        )
        for offset: CGFloat in [1.1, -1.9] {
            plug.append(NSBezierPath(rect: NSRect(x: centre.x + 0.8, y: centre.y + offset, width: 2.2, height: 0.8)))
        }
        plug.append(NSBezierPath(rect: NSRect(x: centre.x - 4.4, y: centre.y - 0.4, width: 1.8, height: 0.8)))
        punchOut(plug)
    }

    private func punchOut(_ glyph: NSBezierPath) {
        NSColor.black.withAlphaComponent(0.85).setFill()
        glyph.fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        glyph.lineWidth = 0.5
        glyph.stroke()
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
