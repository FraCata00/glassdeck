import AppKit
import GlassDeckKit

/// The compact meter drawn inside the Control Strip slot.
///
/// The Touch Bar is 30 pt tall, so every metric gets a small chip: a level that
/// fills from the bottom, the metric's short name, and its current value.
final class TouchBarStripView: NSView {
    /// Set by the controller on every observation pass, not only when the
    /// selection moves, so an unchanged one must not count as a change: it
    /// used to mark all three meters dirty on every sample, undoing the chip
    /// comparison below.
    var metrics: [MetricKind] = MetricKind.defaultSelection {
        didSet {
            guard metrics != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    /// Redrawn only when a chip would come out different: a snapshot is new on
    /// every sample by its timestamp alone, while what the chips show — a whole
    /// percentage, a level a pixel tall — often has not moved at all.
    var snapshot: MetricsSnapshot = .empty {
        didSet { if chips() != drawnChips { needsDisplay = true } }
    }

    /// What one chip shows, down to the pixel and no further.
    private struct Chip: Equatable {
        let value: String
        let level: Int
    }

    /// What the last `draw` put on the bar.
    private var drawnChips: [Chip] = []

    private func chips() -> [Chip] {
        // The level is 28 pt tall on a 2x panel: 56 distinguishable steps.
        metrics.map { Chip(value: shortValue(for: $0), level: (snapshot.fraction(for: $0).clamped01 * 56).roundedInt) }
    }

    /// Width of a single metric chip, chosen so four metrics stay inside the slot
    /// the Control Strip grants a tray item.
    private let chipWidth: CGFloat = 42
    private let chipSpacing: CGFloat = 4

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: CGFloat(max(metrics.count, 1)) * (chipWidth + chipSpacing),
            height: 30
        )
    }

    override var allowsVibrancy: Bool { true }

    // One element for the whole meter: the chips are far too small to be
    // separate targets, so it reads out as a single running summary.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "GlassDeck" }
    override func accessibilityValue() -> Any? {
        metrics.map { "\($0.title) \(snapshot.headline(for: $0))" }.joined(separator: ", ")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(dirtyRect)
        drawnChips = chips()

        for (index, kind) in metrics.enumerated() {
            let origin = CGFloat(index) * (chipWidth + chipSpacing)
            let frame = NSRect(x: origin, y: 1, width: chipWidth, height: bounds.height - 2)
            draw(kind: kind, in: frame, context: context)
        }
    }

    private func draw(kind: MetricKind, in frame: NSRect, context: CGContext) {
        let fraction = snapshot.fraction(for: kind).clamped01
        let path = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)

        Self.chipFill.setFill()
        path.fill()

        // Level fill, clipped to the chip so the rounded corners stay clean.
        context.saveGState()
        path.addClip()
        let fillHeight = max(2, frame.height * fraction)
        let fillRect = NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: fillHeight)
        Self.gradient(for: kind)?.draw(in: fillRect, angle: 90)
        context.restoreGState()

        (kind.shortTitle as NSString).draw(
            in: NSRect(x: frame.minX, y: frame.maxY - 12, width: frame.width, height: 10),
            withAttributes: Self.titleAttributes
        )
        (shortValue(for: kind) as NSString).draw(
            in: NSRect(x: frame.minX, y: frame.minY + 3, width: frame.width, height: 13),
            withAttributes: Self.valueAttributes
        )
    }

    // The fills, fonts and attributes are the same on every draw, so they are
    // built once rather than per chip per redraw.
    private static let chipFill = NSColor.white.withAlphaComponent(0.10)

    private static let titleAttributes = attributes(
        font: .systemFont(ofSize: 7.5, weight: .semibold),
        color: .white.withAlphaComponent(0.75)
    )
    private static let valueAttributes = attributes(
        font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
        color: .white
    )

    private static func attributes(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    /// Each metric's level gradient, made on its first draw.
    private static var gradients: [MetricKind: NSGradient] = [:]

    private static func gradient(for kind: MetricKind) -> NSGradient? {
        if let cached = gradients[kind] { return cached }
        let color = TouchBarPalette.color(for: kind)
        let gradient = NSGradient(colors: [color.withAlphaComponent(0.95), color.withAlphaComponent(0.45)])
        gradients[kind] = gradient
        return gradient
    }

    /// Values are abbreviated hard: `42%`, `9G`, `1.4M` — anything longer is unreadable at this size.
    private func shortValue(for kind: MetricKind) -> String {
        switch kind {
        case .cpu, .gpu, .memory, .disk:
            ValueFormatter.percent(snapshot.fraction(for: kind))
        case .network:
            TouchBarPalette.compactRate(snapshot.network.downloadBytesPerSecond)
        case .fans:
            TouchBarPalette.compactRPM(snapshot.fans.topRPM, isAvailable: snapshot.fans.isAvailable)
        case .battery:
            snapshot.battery.headline
        case .temperature:
            snapshot.thermal.hottest.map { "\($0.roundedInt)°" } ?? "–"
        case .power:
            snapshot.power.isAvailable ? "\(snapshot.power.watts.roundedInt)W" : "–"
        }
    }
}

/// Colours and abbreviations shared by both Touch Bar surfaces.
enum TouchBarPalette {
    /// The app's one accent per metric, so a metric is the same colour on
    /// the Touch Bar as in the panel and the menu bar.
    static func color(for kind: MetricKind) -> NSColor {
        Theme.nsAccent(kind)
    }

    /// The terminal style's two weights, shared by the panels and the detail.
    @MainActor static let terminalFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    @MainActor static let terminalBoldFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)

    /// Advance of one character in the terminal style's font, measured once.
    /// Every glyph in a monospaced font has it, so a line's width is a count.
    @MainActor static let terminalCharacterWidth: CGFloat = {
        max(1, ("0" as NSString).size(withAttributes: [.font: terminalFont]).width)
    }()

    /// The background a style puts behind an item: a chip, a leading hairline,
    /// or nothing. Shared by the panels and the battery chip so the two match.
    static func drawChrome(_ chrome: TouchBarStyle.Chrome, in bounds: NSRect) {
        switch chrome {
        case .chip: fillChip(Theme.TouchBar.chip, in: bounds, radius: Theme.TouchBar.chipRadius)
        case .hairline:
            Theme.TouchBar.hairline.setFill()
            NSRect(x: bounds.minX, y: bounds.minY + 3, width: 1, height: bounds.height - 6).fill()
        case .none: break
        }
    }

    /// A rounded fill one point in from the top and bottom, the shape every
    /// Touch Bar chip has.
    static func fillChip(_ colour: NSColor, in bounds: NSRect, radius: CGFloat) {
        colour.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: radius, yRadius: radius).fill()
    }

    /// `1.4k`, `820` — fan speed squeezed into four characters.
    static func compactRPM(_ rpm: Double, isAvailable: Bool) -> String {
        guard isAvailable else { return "–" }
        guard rpm > 0 else { return "off" }
        return rpm >= 1_000 ? "\(ValueFormatter.fixed(rpm / 1_000, places: 1))k" : "\(Int(rpm))"
    }

    /// `1.4M`, `820K` — throughput squeezed into four characters.
    static func compactRate(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        switch value {
        case ..<1_000: return "\(Int(value))B"
        case ..<1_000_000: return "\(Int(value / 1_000))K"
        case ..<10_000_000: return "\(ValueFormatter.fixed(value / 1_000_000, places: 1))M"
        default: return "\(Int(value / 1_000_000))M"
        }
    }
}
