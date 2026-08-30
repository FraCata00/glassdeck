import AppKit
import GlassDeckKit

/// Draws the status item image.
///
/// The menu bar is redrawn on every sample, so the glyph is rendered straight
/// into an `NSImage` rather than going through SwiftUI's renderer.
enum MenuBarGlyph {
    /// A miniature bar chart, one coloured column per metric.
    static func bars(for snapshot: MetricsSnapshot, metrics: [MetricKind]) -> NSImage {
        let barWidth: CGFloat = 3.5
        let spacing: CGFloat = 2.5
        let height: CGFloat = 15
        let count = max(metrics.count, 1)
        let width = CGFloat(count) * barWidth + CGFloat(count - 1) * spacing

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            for (index, kind) in metrics.enumerated() {
                let x = CGFloat(index) * (barWidth + spacing)
                let fraction = snapshot.fraction(for: kind).clamped01

                let track = NSBezierPath(
                    roundedRect: NSRect(x: x, y: 0, width: barWidth, height: height),
                    xRadius: barWidth / 2,
                    yRadius: barWidth / 2
                )
                NSColor.labelColor.withAlphaComponent(0.22).setFill()
                track.fill()

                let filledHeight = max(barWidth, height * fraction)
                let bar = NSBezierPath(
                    roundedRect: NSRect(x: x, y: 0, width: barWidth, height: filledHeight),
                    xRadius: barWidth / 2,
                    yRadius: barWidth / 2
                )
                NSColor(hue: kind.hue, saturation: 0.7, brightness: 0.95, alpha: 1).setFill()
                bar.fill()
            }
            return true
        }
        // Colour carries the meaning here, so the image must not be tinted by the system.
        image.isTemplate = false
        return image
    }
}
