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

        // Narrow panels give the label less room, so they fall back to the short
        // title ("RAM" instead of "MEMORY") and hand the saved width to the graph.
        let isCompact = width < 120
        let labelWidth = isCompact ? bounds.width * 0.40 : bounds.width * 0.42
        let sparklineRect = NSRect(
            x: labelWidth + 10,
            y: 4,
            width: bounds.width - labelWidth - 16,
            height: bounds.height - 8
        )
        drawSparkline(in: sparklineRect, color: color)

        draw(
            text: isCompact ? kind.shortTitle : kind.title.uppercased(),
            in: NSRect(x: 8, y: bounds.height - 14, width: labelWidth, height: 11),
            font: .systemFont(ofSize: 8, weight: .semibold),
            color: color.withAlphaComponent(0.9),
            alignment: .left
        )
        draw(
            text: compactHeadline(isCompact: isCompact),
            in: NSRect(x: 8, y: 3, width: labelWidth, height: 14),
            font: .monospacedDigitSystemFont(ofSize: isCompact ? 11 : 12, weight: .semibold),
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

    /// Byte-valued metrics are shown as a percentage on the narrow panels, where
    /// "5.5 GB" would not fit beside the graph.
    private func compactHeadline(isCompact: Bool) -> String {
        guard isCompact, kind == .memory || kind == .disk else {
            return snapshot.headline(for: kind)
        }
        return ValueFormatter.percent(snapshot.fraction(for: kind))
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
