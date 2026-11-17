import AppKit
import GlassDeckKit

/// The expanded view of one metric, filling the Touch Bar: headline on the left,
/// the numbers behind it in the middle, and the history on the right.
///
/// Drawn in the style chosen for the bar, with the same pieces the panels use,
/// so tapping a panel opens it rather than changing to a different look. The
/// detail always shows the history — it is what the bar is opened for — and a
/// style whose panel has none draws it here in its own manner.
final class TouchBarDetailView: NSView {
    var kind: MetricKind = .cpu {
        didSet { cachedInk = nil; needsDisplay = true }
    }
    var snapshot: MetricsSnapshot = .empty { didSet { needsDisplay = true } }
    var history: [Double] = [] { didSet { needsDisplay = true } }
    var style: TouchBarStyle = .glass {
        didSet {
            guard style != oldValue else { return }
            cachedInk = nil
            needsDisplay = true
        }
    }
    var onTap: (() -> Void)?

    /// The detail's width on the bar. The settings preview draws at it too,
    /// so the miniature is the bar's own layout.
    static let barWidth: CGFloat = 856

    private let width: CGFloat

    init(width: CGFloat = TouchBarDetailView.barWidth) {
        self.width = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: width, height: 30) }
    override var allowsVibrancy: Bool { true }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { kind.title }
    override func accessibilityValue() -> Any? {
        // The headline plus the numbers behind it, which is what the bar shows.
        ([snapshot.headline(for: kind)] + snapshot.details(for: kind).map { "\($0.label) \($0.value)" })
            .joined(separator: ", ")
    }

    override func touchesBegan(with event: NSEvent) {
        super.touchesBegan(with: event)
        onTap?()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onTap?()
    }

    // MARK: - Drawing

    /// The fonts and colours a style sets its text in.
    private struct Ink {
        var title: (font: NSFont, color: NSColor)
        var headline: (font: NSFont, color: NSColor)
        var label: (font: NSFont, color: NSColor)
        var value: (font: NSFont, color: NSColor)
        var kern: CGFloat = 0
    }

    /// The ink for the current style and metric, built once rather than on
    /// every sample: it changes only when one of the two does.
    private var cachedInk: Ink?

    private var fraction: Double { snapshot.fraction(for: kind).clamped01 }

    /// Where a pet sits when it turns up in the detail: in the headline
    /// column, after its text. The title and the figure take well under
    /// 120 pt even in the longest language, and the column runs to 156.
    var petSlot: NSPoint {
        NSPoint(x: (style == .rings ? 40 : 12) + 124, y: 5)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(dirtyRect)

        let accent = TouchBarPalette.color(for: kind)
        var ink = cachedInk ?? Self.ink(for: style, accent: accent)
        cachedInk = ink
        drawBackground(accent: accent, context: context, ink: &ink)

        // The ring sits ahead of the headline; every other style starts with it.
        var headlineX: CGFloat = 12
        if style == .rings {
            TouchBarPaint.ring(fraction, centre: NSPoint(x: 12 + 10, y: bounds.midY), radius: 9.5, color: accent)
            headlineX = 40
        }
        drawText(kind.title.uppercased(), in: NSRect(x: headlineX, y: bounds.height - 14, width: 150, height: 11), ink.title, kern: ink.kern)
        drawText(snapshot.headline(for: kind), in: NSRect(x: headlineX, y: 3, width: 150, height: 16), ink.headline)

        // The ambient style's history is the backdrop, which leaves the right
        // of the bar to the numbers.
        let graphWidth: CGFloat = style == .ambient ? 0 : 210
        let columnsStart = headlineX + 156
        let columnsWidth = bounds.width - columnsStart - graphWidth - 24
        drawDetails(from: columnsStart, width: columnsWidth, ink: ink)

        if graphWidth > 0 {
            let graph = NSRect(x: bounds.width - graphWidth - 12, y: 5, width: graphWidth, height: 20)
            drawHistory(in: graph, accent: accent, ink: ink)
        }
    }

    /// What a style sets its text in. Every colour but the signal style's is
    /// fixed by the style and the metric; that one is recoloured as drawn.
    private static func ink(for style: TouchBarStyle, accent: NSColor) -> Ink {
        var ink = Ink(
            title: (.systemFont(ofSize: 8, weight: .semibold), accent.withAlphaComponent(0.9)),
            headline: (.monospacedDigitSystemFont(ofSize: 13, weight: .semibold), .white),
            label: (.systemFont(ofSize: 8, weight: .regular), .white.withAlphaComponent(0.55)),
            value: (.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .white)
        )
        switch style {
        case .glass, .histogram:
            break
        case .instrument:
            ink.title = (.systemFont(ofSize: 7, weight: .semibold), .white.withAlphaComponent(0.55))
            ink.headline = (.monospacedSystemFont(ofSize: 14, weight: .medium), .white)
            ink.label = (.systemFont(ofSize: 7, weight: .semibold), .white.withAlphaComponent(0.55))
            ink.value = (.monospacedSystemFont(ofSize: 12, weight: .medium), .white)
            ink.kern = 0.6
        case .capsule:
            ink.title = (.systemFont(ofSize: 8.5, weight: .semibold), .white.withAlphaComponent(0.85))
            ink.headline = (.monospacedDigitSystemFont(ofSize: 13, weight: .bold), .white)
        case .ambient:
            ink.title = (.systemFont(ofSize: 7, weight: .semibold), .white.withAlphaComponent(0.72))
            ink.headline = (.monospacedDigitSystemFont(ofSize: 14, weight: .bold), .white)
            ink.label = (.systemFont(ofSize: 8, weight: .regular), .white.withAlphaComponent(0.72))
        case .rings:
            ink.title = (.systemFont(ofSize: 7, weight: .semibold), .white.withAlphaComponent(0.55))
            ink.kern = 0.4
        case .terminal:
            // Names a size down from the figures, so two lines fit the bar.
            let phosphor = Theme.nsPhosphor
            ink = Ink(
                title: (terminalSmallFont, phosphor.withAlphaComponent(0.55)),
                headline: (TouchBarPalette.terminalBoldFont, phosphor),
                label: (terminalSmallFont, phosphor.withAlphaComponent(0.55)),
                value: (TouchBarPalette.terminalBoldFont, phosphor)
            )
        case .signal:
            ink.title.font = .systemFont(ofSize: 8, weight: .bold)
            ink.headline.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
            ink.value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        case .tinted:
            ink.title = (.systemFont(ofSize: 8, weight: .semibold), .white.withAlphaComponent(0.75))
            ink.headline = (.monospacedDigitSystemFont(ofSize: 13, weight: .bold), accent)
        }
        return ink
    }

    /// Paints what sits behind the text. The signal style's background says
    /// the state, and its text takes the colour that reads on it.
    private func drawBackground(accent: NSColor, context: CGContext, ink: inout Ink) {
        switch style {
        case .glass, .histogram:
            TouchBarPalette.drawChrome(.chip, in: bounds)
        case .capsule:
            TouchBarPaint.capsule(fraction, in: bounds.insetBy(dx: 1, dy: 2), color: accent, context: context)
        case .ambient:
            TouchBarPaint.ambient(history, in: bounds, color: accent, context: context)
        case .tinted:
            TouchBarPaint.tint(level: fraction, in: bounds.insetBy(dx: 0.5, dy: 1.5), color: accent, context: context)
        case .signal:
            let text = TouchBarPaint.signal(snapshot.strain(for: kind), in: bounds, radius: 6)
            ink.title.color = text
            ink.headline.color = text
            ink.label.color = text.withAlphaComponent(0.7)
            ink.value.color = text
        case .instrument, .rings, .terminal:
            break
        }
    }

    private func drawDetails(from start: CGFloat, width: CGFloat, ink: Ink) {
        let details = Array(snapshot.details(for: kind).prefix(5))
        guard !details.isEmpty else { return }
        let columnWidth = width / CGFloat(details.count)

        for (index, detail) in details.enumerated() {
            let x = start + CGFloat(index) * columnWidth
            // The instrument divides its readings with hairlines, as it divides
            // the panels on the bar.
            if style == .instrument {
                Theme.TouchBar.hairline.setFill()
                NSRect(x: x - 6, y: 5, width: 1, height: bounds.height - 10).fill()
            }
            drawText(detail.label, in: NSRect(x: x, y: bounds.height - 14, width: columnWidth - 8, height: 11), ink.label, kern: ink.kern)
            drawText(detail.value, in: NSRect(x: x, y: 4, width: columnWidth - 8, height: 14), ink.value)
        }
    }

    private func drawHistory(in rect: NSRect, accent: NSColor, ink: Ink) {
        switch style {
        case .glass, .tinted:
            TouchBarPaint.curve(history, in: rect, color: accent, lineWidth: 1.6, fillAlpha: 0.18)
        case .capsule:
            TouchBarPaint.curve(history, in: rect, color: .white.withAlphaComponent(0.8), lineWidth: 1.4, fillAlpha: 0)
        case .rings:
            TouchBarPaint.curve(history, in: rect, color: accent, lineWidth: 1.4, fillAlpha: 0)
        case .signal:
            TouchBarPaint.curve(history, in: rect, color: ink.headline.color, lineWidth: 1.4, fillAlpha: 0)
        case .instrument:
            TouchBarPaint.meter(fraction, in: rect.insetBy(dx: 0, dy: 4), color: accent)
        case .histogram:
            TouchBarPaint.columns(history, in: rect, color: accent)
        case .terminal:
            let count = Int(rect.width / TouchBarPalette.terminalCharacterWidth)
            let line = TouchBarHistory.sparkline(history, count: count)
            drawText(line, in: NSRect(x: rect.maxX - CGFloat(line.count) * TouchBarPalette.terminalCharacterWidth, y: (bounds.height - 13) / 2, width: rect.width, height: 13), ink.value)
        case .ambient:
            break
        }
    }

    private static let terminalSmallFont = NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)

    private func drawText(_ text: String, in rect: NSRect, _ ink: (font: NSFont, color: NSColor), kern: CGFloat = 0) {
        (text as NSString).draw(in: rect, withAttributes: [.font: ink.font, .foregroundColor: ink.color, .kern: kern])
    }
}
