import AppKit
import GlassDeckKit

/// A metric panel for the expanded Touch Bar: title, live value, and a history
/// curve drawn from the monitor's ring buffer.
final class TouchBarMetricView: NSView {
    let kind: MetricKind

    var snapshot: MetricsSnapshot = .empty { didSet { needsDisplay = true } }
    var history: [Double] = [] { didSet { needsDisplay = true } }
    /// Panels are narrower on the shorter bar that leaves the Control Strip in place.
    var width: CGFloat = 168 { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    /// Tapping a panel expands it into the metric's own bar.
    var onTap: (() -> Void)?

    init(kind: MetricKind) {
        self.kind = kind
        super.init(frame: NSRect(x: 0, y: 0, width: 168, height: 30))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: width, height: 30) }
    override var allowsVibrancy: Bool { true }

    // The panel is drawn, not composed of controls, so VoiceOver sees nothing
    // unless it is told. Read live rather than set once: the value changes on
    // every sample.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { kind.title }
    override func accessibilityValue() -> Any? { snapshot.headline(for: kind) }
    override func accessibilityHelp() -> String? { snapshot.caption(for: kind) }

    override func touchesBegan(with event: NSEvent) {
        super.touchesBegan(with: event)
        onTap?()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onTap?()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(dirtyRect)

        let color = TouchBarPalette.color(for: kind)
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 7, yRadius: 7)
        NSColor.white.withAlphaComponent(0.08).setFill()
        background.fill()

        // Narrow panels hand more width to the graph; what the text says is then
        // decided by measuring it, not by the same threshold.
        let isCompact = width < 120
        let labelWidth = isCompact ? bounds.width * 0.40 : bounds.width * 0.42
        let sparklineRect = NSRect(
            x: labelWidth + 10,
            y: 4,
            width: bounds.width - labelWidth - 16,
            height: bounds.height - 8
        )
        drawSparkline(in: sparklineRect, color: color)

        let titleFont = NSFont.systemFont(ofSize: 8, weight: .semibold)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: isCompact ? 11 : 12, weight: .semibold)

        draw(
            text: Self.fitting([kind.title.uppercased(), kind.shortTitle], font: titleFont, within: labelWidth),
            in: NSRect(x: 8, y: bounds.height - 14, width: labelWidth, height: 11),
            font: titleFont,
            color: color.withAlphaComponent(0.9),
            alignment: .left
        )
        draw(
            text: Self.fitting(headlineCandidates, font: valueFont, within: labelWidth),
            in: NSRect(x: 8, y: 3, width: labelWidth, height: 14),
            font: valueFont,
            color: .white,
            alignment: .left
        )
    }

    private func drawSparkline(in rect: NSRect, color: NSColor) {
        guard history.count > 1 else { return }
        let window = Self.window(for: history)
        let step = rect.width / CGFloat(history.count - 1)
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        for (index, value) in history.enumerated() {
            let normalised = (value.clamped01 - window.lowerBound) / (window.upperBound - window.lowerBound)
            let point = NSPoint(
                x: rect.minX + CGFloat(index) * step,
                y: rect.minY + CGFloat(normalised.clamped01) * (rect.height - 2) + 1
            )
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }

        // Faint fill under the curve, then the stroke on top.
        let fill = path.copy() as! NSBezierPath
        fill.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        fill.line(to: NSPoint(x: rect.minX, y: rect.minY))
        fill.close()
        color.withAlphaComponent(0.18).setFill()
        fill.fill()

        color.setStroke()
        path.stroke()
    }

    /// What the value could say, best first. Byte- and rate-valued metrics fall
    /// back to a percentage, which always fits.
    private var headlineCandidates: [String] {
        let headline = snapshot.headline(for: kind)
        switch kind {
        case .memory, .disk, .network:
            return [headline, ValueFormatter.percent(snapshot.fraction(for: kind))]
        default:
            return [headline]
        }
    }

    /// The first candidate that fits the space, or the last as a fallback.
    ///
    /// Measured rather than guessed from the panel width: widening the panels
    /// to fill the bar also let them show full titles, and "TEMPERATURE" was
    /// then quietly clipped to "TEMPERATU" at widths where "TMP" would have
    /// been fine.
    private static func fitting(_ candidates: [String], font: NSFont, within width: CGFloat) -> String {
        candidates.first { ($0 as NSString).size(withAttributes: [.font: font]).width <= width }
            ?? candidates.last ?? ""
    }

    /// Vertical range the curve is drawn in.
    ///
    /// Metrics such as memory and disk barely move, and drawing them against the
    /// full 0–100 % scale turns the curve into a flat slab. When the observed
    /// spread is small the window zooms in around it, which is what makes the
    /// Touch Bar graph worth glancing at.
    private static func window(for values: [Double]) -> ClosedRange<Double> {
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 1
        let spread = maximum - minimum
        guard spread < 0.08 else { return minimum...maximum }
        let centre = (minimum + maximum) / 2
        let lower = max(0, centre - 0.04)
        return lower...(lower + 0.08)
    }

    private func draw(
        text: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        ).draw(in: rect)
    }
}
