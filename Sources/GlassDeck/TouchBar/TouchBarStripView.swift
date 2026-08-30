import AppKit
import GlassDeckKit

/// The compact meter drawn inside the Control Strip slot.
///
/// The Touch Bar is 30 pt tall, so every metric gets a small chip: a level that
/// fills from the bottom, the metric's short name, and its current value.
final class TouchBarStripView: NSView {
    var metrics: [MetricKind] = MetricKind.defaultSelection { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var snapshot: MetricsSnapshot = .empty { didSet { needsDisplay = true } }

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

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(dirtyRect)

        for (index, kind) in metrics.enumerated() {
            let origin = CGFloat(index) * (chipWidth + chipSpacing)
            let frame = NSRect(x: origin, y: 1, width: chipWidth, height: bounds.height - 2)
            draw(kind: kind, in: frame, context: context)
        }
    }

    private func draw(kind: MetricKind, in frame: NSRect, context: CGContext) {
        let fraction = snapshot.fraction(for: kind).clamped01
        let path = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)

        NSColor.white.withAlphaComponent(0.10).setFill()
        path.fill()

        // Level fill, clipped to the chip so the rounded corners stay clean.
        context.saveGState()
        path.addClip()
        let fillHeight = max(2, frame.height * fraction)
        let fillRect = NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: fillHeight)
        let color = TouchBarPalette.color(for: kind)
        let gradient = NSGradient(
            colors: [color.withAlphaComponent(0.95), color.withAlphaComponent(0.45)]
        )
        gradient?.draw(in: fillRect, angle: 90)
        context.restoreGState()

        let title = kind.shortTitle
        let value = shortValue(for: kind)

        draw(
            text: title,
            in: NSRect(x: frame.minX, y: frame.maxY - 12, width: frame.width, height: 10),
            font: .systemFont(ofSize: 7.5, weight: .semibold),
            color: .white.withAlphaComponent(0.75)
        )
        draw(
            text: value,
            in: NSRect(x: frame.minX, y: frame.minY + 3, width: frame.width, height: 13),
            font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            color: .white
        )
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
            snapshot.thermal.hottest.map { "\(Int($0.rounded()))°" } ?? "–"
        case .power:
            snapshot.power.isAvailable ? "\(Int(snapshot.power.watts.rounded()))W" : "–"
        }
    }

    private func draw(text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        NSAttributedString(string: text, attributes: attributes).draw(in: rect)
    }
}

/// Colours and abbreviations shared by both Touch Bar surfaces.
enum TouchBarPalette {
    static func color(for kind: MetricKind) -> NSColor {
        NSColor(hue: kind.hue, saturation: 0.75, brightness: 1.0, alpha: 1.0)
    }

    /// `1.4k`, `820` — fan speed squeezed into four characters.
    static func compactRPM(_ rpm: Double, isAvailable: Bool) -> String {
        guard isAvailable else { return "–" }
        guard rpm > 0 else { return "off" }
        return rpm >= 1_000 ? String(format: "%.1fk", rpm / 1_000) : "\(Int(rpm))"
    }

    /// `1.4M`, `820K` — throughput squeezed into four characters.
    static func compactRate(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        switch value {
        case ..<1_000: return "\(Int(value))B"
        case ..<1_000_000: return "\(Int(value / 1_000))K"
        case ..<10_000_000: return String(format: "%.1fM", value / 1_000_000)
        default: return "\(Int(value / 1_000_000))M"
        }
    }
}
