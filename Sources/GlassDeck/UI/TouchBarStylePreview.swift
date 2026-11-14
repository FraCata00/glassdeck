import AppKit
import GlassDeckKit
import SwiftUI

/// Two real Touch Bar panels drawn in a given style, for the style picker.
///
/// The actual `TouchBarMetricView`, not a picture of it, so the preview cannot
/// drift from what the bar draws. Fed a fixed sample rather than the live
/// snapshot: nine previews redrawing on every tick would cost more than the
/// Touch Bar itself, and a still preview is easier to compare.
struct TouchBarStylePreview: NSViewRepresentable {
    let style: TouchBarStyle

    func makeNSView(context: Context) -> PreviewView { PreviewView() }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.style = style
    }

    final class PreviewView: NSView {
        private let panels: [TouchBarMetricView] = [MetricKind.cpu, .memory].map { kind in
            let view = TouchBarMetricView(kind: kind)
            view.snapshot = PreviewSample.snapshot
            view.history = PreviewSample.history(for: kind)
            return view
        }

        var style: TouchBarStyle = .glass {
            didSet { for panel in panels { panel.style = style } }
        }

        init() {
            super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 30))
            for panel in panels { addSubview(panel) }
            setAccessibilityElement(false)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 30) }

        override func layout() {
            super.layout()
            let gap: CGFloat = 4
            let width = (bounds.width - gap) / CGFloat(panels.count)
            for (index, panel) in panels.enumerated() {
                panel.width = width
                panel.frame = NSRect(x: CGFloat(index) * (width + gap), y: (bounds.height - 30) / 2, width: width, height: 30)
            }
        }
    }
}

/// The same view the bar shows when a panel is tapped, in a given style.
///
/// Laid out at the bar's own width and scaled down through its container's
/// bounds rather than laid out narrower, so the preview is the bar's layout in
/// miniature — still vector-sharp — rather than a cramped variant of it.
struct TouchBarDetailPreview: NSViewRepresentable {
    let style: TouchBarStyle

    private static let barSize = NSSize(width: TouchBarDetailView.barWidth, height: 30)
    static let aspectRatio = barSize.width / barSize.height

    func makeNSView(context: Context) -> ScaledView { ScaledView() }

    func updateNSView(_ view: ScaledView, context: Context) {
        view.detail.style = style
    }

    final class ScaledView: NSView {
        let detail = TouchBarDetailView()

        init() {
            super.init(frame: NSRect(origin: .zero, size: barSize))
            detail.kind = .cpu
            detail.snapshot = PreviewSample.snapshot
            detail.history = PreviewSample.history(for: .cpu)
            detail.frame = NSRect(origin: .zero, size: barSize)
            addSubview(detail)
            setAccessibilityElement(false)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }

        // Whatever frame SwiftUI gives, the content is drawn as on the bar.
        override func layout() {
            super.layout()
            if bounds.size != barSize { setBoundsSize(barSize) }
        }
    }
}

/// A plausible, mildly busy Mac for the previews: enough load that every style
/// has something to fill, and memory full but healthy, as it usually is.
/// Fixed rather than live: nine previews redrawing on every tick would cost
/// more than the Touch Bar itself, and a still preview is easier to compare.
private enum PreviewSample {
    static let snapshot: MetricsSnapshot = {
        var snapshot = MetricsSnapshot.empty
        snapshot.cpu = CPUUsage(user: 0.16, system: 0.07, idle: 0.77)
        snapshot.memory = MemoryUsage(
            total: 16 << 30,
            appMemory: 8 << 30,
            wired: 2 << 30,
            compressed: 1 << 30,
            free: 1 << 30,
            availableFraction: 0.42
        )
        return snapshot
    }()

    static func history(for kind: MetricKind) -> [Double] {
        let (base, amplitude, seed) = kind == .cpu ? (0.24, 0.12, 1.1) : (0.7, 0.03, 0.4)
        return (0..<40).map { index in
            let i = Double(index)
            return (base + amplitude * (sin(i * 0.37 * seed + seed) * 0.6 + sin(i * 1.13 + seed * 2) * 0.4)).clamped01
        }
    }
}
