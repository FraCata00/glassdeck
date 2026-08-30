import AppKit
import GlassDeckKit

/// The expanded view of one metric, filling the Touch Bar: headline on the left,
/// the numbers behind it in the middle, and the history on the right.
final class TouchBarDetailView: NSView {
    var kind: MetricKind = .cpu { didSet { needsDisplay = true } }
    var snapshot: MetricsSnapshot = .empty { didSet { needsDisplay = true } }
    var history: [Double] = [] { didSet { needsDisplay = true } }
    var onTap: (() -> Void)?

    private let width: CGFloat

    init(width: CGFloat) {
        self.width = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
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

        let accent = TouchBarPalette.color(for: kind)
        NSColor.white.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 7, yRadius: 7).fill()

        // Headline block.
        draw(
            text: kind.title.uppercased(),
            in: NSRect(x: 12, y: bounds.height - 14, width: 150, height: 11),
            font: .systemFont(ofSize: 8, weight: .semibold),
            color: accent.withAlphaComponent(0.9)
        )
        draw(
            text: snapshot.headline(for: kind),
            in: NSRect(x: 12, y: 3, width: 150, height: 15),
            font: .monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            color: .white
        )

        // Detail columns.
        let details = Array(snapshot.details(for: kind).prefix(5))
        let columnsStart: CGFloat = 168
        let sparklineWidth: CGFloat = 210
        let columnsWidth = bounds.width - columnsStart - sparklineWidth - 24
        let columnWidth = details.isEmpty ? 0 : columnsWidth / CGFloat(details.count)

        for (index, detail) in details.enumerated() {
            let x = columnsStart + CGFloat(index) * columnWidth
            draw(
                text: detail.label,
                in: NSRect(x: x, y: bounds.height - 14, width: columnWidth - 8, height: 11),
                font: .systemFont(ofSize: 8, weight: .regular),
                color: .white.withAlphaComponent(0.55)
            )
            draw(
                text: detail.value,
                in: NSRect(x: x, y: 4, width: columnWidth - 8, height: 14),
                font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                color: .white
            )
        }

        drawSparkline(
            in: NSRect(x: bounds.width - sparklineWidth - 12, y: 5, width: sparklineWidth, height: 20),
            color: accent
        )
    }

    private func drawSparkline(in rect: NSRect, color: NSColor) {
        guard history.count > 1 else { return }
        let minimum = history.min() ?? 0
        let maximum = history.max() ?? 1
        let spread = maximum - minimum
        // Same zoom rule as the compact panels: a flat curve should still show
        // its shape rather than reading as a filled slab.
        let lower = spread < 0.08 ? max(0, (minimum + maximum) / 2 - 0.04) : minimum
        let upper = spread < 0.08 ? lower + 0.08 : maximum

        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        let step = rect.width / CGFloat(history.count - 1)
        for (index, value) in history.enumerated() {
            let normalised = ((value.clamped01 - lower) / (upper - lower)).clamped01
            let point = NSPoint(x: rect.minX + CGFloat(index) * step, y: rect.minY + CGFloat(normalised) * rect.height)
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        color.setStroke()
        path.stroke()
    }

    private func draw(text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: color]
        ).draw(in: rect)
    }
}
