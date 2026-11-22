import AppKit
import GlassDeckKit

/// A metric panel for the expanded Touch Bar: title, live value, and — in the
/// styles that have one — a picture of the history from the monitor's ring
/// buffer.
///
/// Every style is drawn here rather than in a view of its own: the panel is
/// rebuilt with the bar, the style can change while it is up, and the text
/// fitting and accessibility below are the same whatever the paint.
final class TouchBarMetricView: NSView {
    let kind: MetricKind

    /// Redrawn only when the panel would come out different, as the Control
    /// Strip meter is: a snapshot is new on every sample by its timestamp
    /// alone, while memory, temperature, fans and power — and every panel of
    /// a style without a history — often read the same from one sample to
    /// the next.
    var snapshot: MetricsSnapshot = .empty {
        didSet {
            let look = Look(snapshot, kind: kind, width: width)
            guard look != self.look else { return }
            self.look = look
            needsDisplay = true
        }
    }
    /// Only set for styles that draw it: the controller does not copy the ring
    /// buffer into a panel that would not look at it. A metric that holds
    /// still, such as a disk at rest, hands over the same buffer every sample.
    var history: [Double] = [] {
        didSet { if history != oldValue { needsDisplay = true } }
    }

    /// Everything a panel takes from the snapshot, down to the pixel and no
    /// further. The candidates are also what `draw` sets, so the value is
    /// formatted once a sample however many times it is drawn.
    private struct Look: Equatable {
        var candidates: [String]
        /// The fraction in device pixels across the panel: finer than any
        /// gauge draws it, the capsule's fill included.
        var level: Int
        var band: StrainBand
        var pressure: MemoryPressure?

        init(_ snapshot: MetricsSnapshot, kind: MetricKind, width: CGFloat) {
            let headline = snapshot.headline(for: kind)
            switch kind {
            // Byte- and rate-valued metrics fall back to a percentage, which
            // always fits.
            case .memory, .disk, .network:
                candidates = [headline, ValueFormatter.percent(snapshot.fraction(for: kind))]
            default:
                candidates = [headline]
            }
            level = Int((snapshot.fraction(for: kind).clamped01 * Double(width) * 2).rounded())
            band = StrainBand(strain: snapshot.strain(for: kind))
            pressure = kind == .memory ? snapshot.memory.pressureLevel : nil
        }
    }

    private var look: Look
    /// Panels are narrower on the shorter bar that leaves the Control Strip in place.
    var width: CGFloat = 168 {
        didSet {
            guard width != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    var style: TouchBarStyle = .glass {
        didSet {
            guard style != oldValue else { return }
            // The fitted text depends on the font, which the style chooses.
            fittedTitle = nil
            fittedValue = nil
            needsDisplay = true
        }
    }

    /// The last answer `fitting` gave for the title and for the value.
    ///
    /// Measuring text was more than half of what drawing a panel cost, and it
    /// was done twice on every sample for strings that had not changed: the
    /// title never does, and the value only when the reading moves.
    private var fittedTitle: Fit?
    private var fittedValue: Fit?

    private struct Fit {
        let candidates: [String]
        let width: CGFloat
        let text: String
    }
    /// Tapping a panel expands it into the metric's own bar.
    var onTap: (() -> Void)?

    init(kind: MetricKind) {
        self.kind = kind
        look = Look(.empty, kind: kind, width: 168)
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

    private var isCompact: Bool { bounds.width < 120 }
    private var fraction: Double { snapshot.fraction(for: kind).clamped01 }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(dirtyRect)

        let color = TouchBarPalette.color(for: kind)
        switch style {
        case .glass: drawGlass(color: color)
        case .instrument: drawInstrument(color: color)
        case .capsule: drawCapsule(color: color, context: context)
        case .ambient: drawAmbient(color: color, context: context)
        case .rings: drawRings(color: color)
        case .terminal: drawTerminal()
        case .histogram: drawHistogram(color: color)
        case .signal: drawSignal()
        case .tinted: drawTinted(color: color, context: context)
        }
        if style.marksMemoryPressure { drawPressureDot() }
    }

    // MARK: - Styles

    private func drawGlass(color: NSColor) {
        TouchBarPalette.drawChrome(style.chrome, in: bounds)

        // Narrow panels hand more width to the graph; what the text says is then
        // decided by measuring it, not by the same threshold.
        let labelWidth = bounds.width * (isCompact ? 0.40 : 0.42)
        let sparklineRect = NSRect(x: labelWidth + 10, y: 4, width: bounds.width - labelWidth - 16, height: bounds.height - 8)
        TouchBarPaint.curve(history, in: sparklineRect, color: color, lineWidth: 1.6, fillAlpha: 0.18)
        drawLabelStack(
            x: 8,
            width: labelWidth,
            titleFont: .systemFont(ofSize: 8, weight: .semibold),
            titleColor: color.withAlphaComponent(0.9),
            valueFont: .monospacedDigitSystemFont(ofSize: isCompact ? 11 : 12, weight: .semibold),
            valueColor: .white
        )
    }

    /// The cheapest style to draw after the terminal: the meter has no path.
    private func drawInstrument(color: NSColor) {
        TouchBarPalette.drawChrome(style.chrome, in: bounds)

        let labelWidth = bounds.width * (isCompact ? 0.46 : 0.42)
        drawLabelStack(
            x: 8,
            width: labelWidth,
            titleFont: .systemFont(ofSize: 7, weight: .semibold),
            titleColor: .white.withAlphaComponent(0.55),
            valueFont: .monospacedSystemFont(ofSize: isCompact ? 12 : 13, weight: .medium),
            valueColor: .white,
            kern: 0.6
        )

        let region = NSRect(x: 8 + labelWidth + 4, y: (bounds.height - 12) / 2, width: bounds.width - labelWidth - 18, height: 12)
        TouchBarPaint.meter(fraction, in: region, color: color)
    }

    private func drawCapsule(color: NSColor, context: CGContext) {
        let rect = bounds.insetBy(dx: 1, dy: 2)
        TouchBarPaint.capsule(fraction, in: rect, color: color, context: context)

        drawRow(
            in: rect.insetBy(dx: 10, dy: 0),
            titleFont: .systemFont(ofSize: 8.5, weight: .semibold),
            titleColor: .white.withAlphaComponent(0.85),
            valueFont: .monospacedDigitSystemFont(ofSize: isCompact ? 11 : 12, weight: .bold),
            valueColor: .white
        )
    }

    /// The most expensive style: a filled path across the whole cell. It is
    /// redrawn at the same cadence as the glass sparkline, no more.
    private func drawAmbient(color: NSColor, context: CGContext) {
        TouchBarPaint.ambient(history, in: bounds, color: color, context: context)

        drawLabelStack(
            x: 7,
            width: bounds.width - 14,
            titleFont: .systemFont(ofSize: 7, weight: .semibold),
            titleColor: .white.withAlphaComponent(0.72),
            valueFont: .monospacedDigitSystemFont(ofSize: isCompact ? 12 : 13, weight: .bold),
            valueColor: .white
        )
    }

    private func drawRings(color: NSColor) {
        TouchBarPaint.ring(fraction, centre: NSPoint(x: 6 + 11, y: bounds.midY), radius: 9.5, color: color)

        drawLabelStack(
            x: 33,
            width: bounds.width - 37,
            titleFont: .systemFont(ofSize: 7, weight: .semibold),
            titleColor: .white.withAlphaComponent(0.55),
            valueFont: .monospacedDigitSystemFont(ofSize: isCompact ? 11 : 12, weight: .semibold),
            valueColor: .white,
            kern: 0.4
        )
    }

    /// One attributed string and nothing else. Its width is worked out by
    /// counting characters, which a monospaced font allows, rather than by
    /// measuring the string on every sample.
    private func drawTerminal() {
        let phosphor = Theme.nsPhosphor
        let characters = Int((bounds.width - 10) / TouchBarPalette.terminalCharacterWidth)
        let layout = TouchBarHistory.terminalLine(
            title: kind.shortTitle,
            candidates: headlineCandidates,
            history: history,
            characters: characters
        )

        let line = NSMutableAttributedString()
        if let title = layout.title {
            line.append(NSAttributedString(string: title + " ", attributes: [.font: TouchBarPalette.terminalFont, .foregroundColor: phosphor.withAlphaComponent(0.55)]))
        }
        line.append(NSAttributedString(string: layout.headline, attributes: [.font: TouchBarPalette.terminalBoldFont, .foregroundColor: phosphor]))
        if !layout.sparkline.isEmpty {
            line.append(NSAttributedString(string: " " + layout.sparkline, attributes: [.font: TouchBarPalette.terminalFont, .foregroundColor: phosphor.withAlphaComponent(0.85)]))
        }
        line.draw(in: NSRect(x: 6, y: (bounds.height - 13) / 2, width: bounds.width - 8, height: 13))
    }


    private func drawHistogram(color: NSColor) {
        TouchBarPalette.drawChrome(style.chrome, in: bounds)

        let labelWidth = bounds.width * 0.40
        drawLabelStack(
            x: 7,
            width: labelWidth,
            titleFont: .systemFont(ofSize: 7, weight: .semibold),
            titleColor: color,
            valueFont: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            valueColor: .white
        )

        let region = NSRect(x: 7 + labelWidth + 4, y: 5, width: bounds.width - labelWidth - 17, height: bounds.height - 10)
        TouchBarPaint.columns(history, in: region, color: color)
    }

    /// Strain, not the fill, picks the colour — so memory that is full but
    /// healthy stays grey, the same rule the panel's dots follow.
    private func drawSignal() {
        let text = TouchBarPaint.signal(snapshot.strain(for: kind), in: bounds, radius: 6)
        drawRow(
            in: bounds.insetBy(dx: 9, dy: 0),
            titleFont: .systemFont(ofSize: 8, weight: .bold),
            titleColor: text,
            valueFont: .monospacedDigitSystemFont(ofSize: isCompact ? 12 : 13, weight: .bold),
            valueColor: text
        )
    }

    private func drawTinted(color: NSColor, context: CGContext) {
        let rect = bounds.insetBy(dx: 0.5, dy: 1.5)
        TouchBarPaint.tint(level: fraction, in: rect, color: color, context: context)

        drawRow(
            in: rect.insetBy(dx: 9, dy: 0).offsetBy(dx: 0, dy: 1),
            titleFont: .systemFont(ofSize: 8, weight: .semibold),
            titleColor: .white.withAlphaComponent(0.75),
            valueFont: .monospacedDigitSystemFont(ofSize: isCompact ? 11.5 : 12.5, weight: .bold),
            valueColor: color
        )
    }

    // MARK: - Pieces

    /// Title above, value below, left-aligned from `x`.
    private func drawLabelStack(
        x: CGFloat,
        width: CGFloat,
        titleFont: NSFont,
        titleColor: NSColor,
        valueFont: NSFont,
        valueColor: NSColor,
        kern: CGFloat = 0
    ) {
        draw(
            text: fitting([kind.title.uppercased(), kind.shortTitle], font: titleFont, within: width, cache: &fittedTitle),
            in: NSRect(x: x, y: bounds.height - 14, width: width, height: 11),
            font: titleFont,
            color: titleColor,
            alignment: .left,
            kern: kern
        )
        draw(
            text: fitting(headlineCandidates, font: valueFont, within: width, cache: &fittedValue),
            in: NSRect(x: x, y: 3, width: width, height: 15),
            font: valueFont,
            color: valueColor,
            alignment: .left
        )
    }

    /// Title on the left and value on the right, on one line.
    private func drawRow(in rect: NSRect, titleFont: NSFont, titleColor: NSColor, valueFont: NSFont, valueColor: NSColor) {
        let valueWidth = rect.width * 0.62
        let titleWidth = rect.width - valueWidth - 4
        draw(
            text: fitting([kind.shortTitle], font: titleFont, within: titleWidth, cache: &fittedTitle),
            in: NSRect(x: rect.minX, y: (bounds.height - 11) / 2, width: titleWidth, height: 11),
            font: titleFont,
            color: titleColor,
            alignment: .left
        )
        draw(
            text: fitting(headlineCandidates, font: valueFont, within: valueWidth, cache: &fittedValue),
            in: NSRect(x: rect.maxX - valueWidth, y: (bounds.height - 15) / 2, width: valueWidth, height: 15),
            font: valueFont,
            color: valueColor,
            alignment: .right
        )
    }

    /// Memory's warning light. The value and the curve show how full RAM is,
    /// which on a Mac is nearly always "very"; this shows when that has turned
    /// into a shortage. Nothing is drawn at normal pressure.
    private func drawPressureDot() {
        guard kind == .memory, snapshot.memory.pressureLevel > .normal else { return }
        let color: NSColor = snapshot.memory.pressureLevel == .critical ? .systemRed : .systemOrange
        let diameter: CGFloat = 5
        let dot = NSRect(x: bounds.maxX - diameter - 6, y: bounds.maxY - diameter - 5, width: diameter, height: diameter)
        color.setFill()
        NSBezierPath(ovalIn: dot).fill()
    }

    /// What the value could say, best first, as worked out when the snapshot
    /// was set.
    private var headlineCandidates: [String] { look.candidates }

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

    /// As above, measured only when the candidates or the width have changed.
    /// The font follows from the width and the style, and a change of style
    /// clears the cache, so it needs no place in the key.
    private func fitting(_ candidates: [String], font: NSFont, within width: CGFloat, cache: inout Fit?) -> String {
        if let cache, cache.candidates == candidates, cache.width == width { return cache.text }
        let text = Self.fitting(candidates, font: font, within: width)
        cache = Fit(candidates: candidates, width: width, text: text)
        return text
    }

    private func draw(
        text: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment,
        kern: CGFloat = 0
    ) {
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: alignment == .right ? Self.rightAligned : Self.leftAligned,
                .kern: kern,
            ]
        )
    }

    // Built once rather than on each of the two text draws per panel per sample.
    private static let leftAligned = paragraphStyle(.left)
    private static let rightAligned = paragraphStyle(.right)

    private static func paragraphStyle(_ alignment: NSTextAlignment) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        return style
    }
}
