import AppKit
import GlassDeckKit

/// The shapes the Touch Bar styles are drawn from, shared by the metric panels
/// and the expanded detail so that a style looks the same in both.
///
/// Every function draws into the current graphics context and keeps nothing:
/// the arithmetic behind them lives in `TouchBarHistory`, where it is tested.
enum TouchBarPaint {
    /// The history as a line, with a faint fill under it down to `floor`
    /// (the bottom of `rect` when not given). A zero `fillAlpha` draws no fill.
    static func curve(
        _ history: [Double],
        in rect: NSRect,
        color: NSColor,
        lineWidth: CGFloat,
        fillAlpha: CGFloat,
        floor: CGFloat? = nil
    ) {
        guard history.count > 1 else { return }
        // A flat curve should still show its shape rather than read as a slab.
        let window = TouchBarHistory.window(for: history)
        let step = rect.width / CGFloat(history.count - 1)
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        for (index, value) in history.enumerated() {
            let normalised = TouchBarHistory.normalised(value, in: window)
            let point = NSPoint(
                x: rect.minX + CGFloat(index) * step,
                y: rect.minY + CGFloat(normalised) * (rect.height - 2) + 1
            )
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }

        if fillAlpha > 0 {
            let bottom = floor ?? rect.minY
            let fill = path.copy() as! NSBezierPath
            fill.line(to: NSPoint(x: rect.maxX, y: bottom))
            fill.line(to: NSPoint(x: rect.minX, y: bottom))
            fill.close()
            color.withAlphaComponent(fillAlpha).setFill()
            fill.fill()
        }

        color.setStroke()
        path.stroke()
    }

    /// A row of segments lit up to `fraction`. Filled rectangles and no path,
    /// which keeps it the cheapest gauge to draw.
    static func meter(_ fraction: Double, in region: NSRect, color: NSColor) {
        let gap: CGFloat = 1.5
        let count = TouchBarHistory.meterSegmentCount(width: region.width)
        let segment = (region.width - gap * CGFloat(count - 1)) / CGFloat(count)
        guard segment >= 1 else { return }
        let lit = TouchBarHistory.litSegments(fraction, count: count)
        for index in 0..<count {
            (index < lit ? color : Theme.TouchBar.track).setFill()
            NSRect(x: region.minX + CGFloat(index) * (segment + gap), y: region.minY, width: segment, height: region.height).fill()
        }
    }

    /// The latest samples as columns, right-aligned so a short history grows in
    /// from where the newest sample is, and the newest at full strength.
    static func columns(_ history: [Double], in region: NSRect, color: NSColor) {
        let count = TouchBarHistory.columnCount(width: region.width)
        let columns = TouchBarHistory.columns(history, count: count)
        guard !columns.isEmpty else { return }
        let gap: CGFloat = 1
        let width = (region.width - gap * CGFloat(count - 1)) / CGFloat(count)
        let start = region.maxX - CGFloat(columns.count) * (width + gap) + gap
        let dimmed = color.withAlphaComponent(0.45)
        for (index, height) in columns.enumerated() {
            (index == columns.count - 1 ? color : dimmed).setFill()
            NSRect(x: start + CGFloat(index) * (width + gap), y: region.minY, width: width, height: region.height * CGFloat(height)).fill()
        }
    }

    /// A ring gauge filled clockwise from twelve o'clock, like the panel's.
    static func ring(_ fraction: Double, centre: NSPoint, radius: CGFloat, color: NSColor) {
        let track = NSBezierPath()
        track.appendArc(withCenter: centre, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = 3
        Theme.TouchBar.track.setStroke()
        track.stroke()

        guard fraction > 0 else { return }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: centre, radius: radius, startAngle: 90, endAngle: 90 - 360 * CGFloat(fraction), clockwise: true)
        arc.lineWidth = 3
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }

    /// A capsule filled up to `fraction` from the leading edge, over a faint
    /// track: the capsule style's gauge.
    static func capsule(_ fraction: Double, in rect: NSRect, color: NSColor, context: CGContext) {
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSColor.white.withAlphaComponent(0.09).setFill()
        path.fill()
        context.saveGState()
        path.addClip()
        color.withAlphaComponent(0.34).setFill()
        NSRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height).fill()
        context.restoreGState()
    }

    /// A rounded cell in the metric's colour with its level as a rule along
    /// the bottom: the tinted style's background.
    static func tint(level fraction: Double, in rect: NSRect, color: NSColor, context: CGContext) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        color.withAlphaComponent(0.18).setFill()
        path.fill()
        path.lineWidth = 0.5
        color.withAlphaComponent(0.4).setStroke()
        path.stroke()
        context.saveGState()
        path.addClip()
        color.setFill()
        NSRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: 2).fill()
        context.restoreGState()
    }

    /// The history filling a whole cell behind its text: the ambient style.
    static func ambient(_ history: [Double], in bounds: NSRect, color: NSColor, context: CGContext) {
        let rect = bounds.insetBy(dx: 0, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.white.withAlphaComponent(0.04).setFill()
        path.fill()
        context.saveGState()
        path.addClip()
        curve(history, in: rect.insetBy(dx: 0, dy: 2), color: color, lineWidth: 1.2, fillAlpha: 0.22, floor: bounds.minY)
        context.restoreGState()
    }

    /// The signal style's background and the colour text takes on it: grey
    /// while calm, the state's colour — with dark text — once strained.
    static func signal(_ strain: Double, in rect: NSRect, radius: CGFloat) -> NSColor {
        let band = StrainBand(strain: strain)
        let isCalm = band == .calm
        TouchBarPalette.fillChip(isCalm ? Theme.TouchBar.chip : Theme.nsStatusTint(band), in: rect, radius: radius)
        return isCalm ? .white.withAlphaComponent(0.78) : .black.withAlphaComponent(0.85)
    }
}
