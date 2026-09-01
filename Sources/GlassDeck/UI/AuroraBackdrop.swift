import GlassDeckKit
import SwiftUI

/// The window's depth: the desktop blurred behind the glass, with a slow colour
/// field drifting over it.
///
/// The field is driven by the sampling tick rather than by a display-link
/// animation — a system monitor that burns CPU on its own decoration would be
/// self-defeating — and its colours lean towards whichever metric is busiest.
struct AuroraBackdrop: View {
    let snapshot: MetricsSnapshot

    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blending: .behindWindow)

            MeshGradient(width: 3, height: 3, points: points, colors: colors)
                .blur(radius: 70)
                .opacity(0.55)
                .animation(.smooth(duration: 2.6), value: phase)
                .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
    }

    /// Advances by a small amount on every sample, so the field drifts at about
    /// the pace of a lava lamp.
    private var phase: Double {
        snapshot.timestamp.timeIntervalSinceReferenceDate / 14
    }

    /// The hottest metric decides how far the field swells.
    private var load: Double {
        max(snapshot.cpu.total, snapshot.gpu.utilisation)
    }

    private var points: [SIMD2<Float>] {
        let drift = { (index: Int, scale: Double) -> Double in
            sin(phase + Double(index) * 1.7) * scale
        }
        let swell = 0.06 + load * 0.08

        return [
            SIMD2(0, 0),
            SIMD2(Float(0.5 + drift(0, swell)), 0),
            SIMD2(1, 0),
            SIMD2(0, Float(0.5 + drift(1, swell))),
            SIMD2(Float(0.5 + drift(2, swell * 1.6)), Float(0.5 + drift(3, swell * 1.6))),
            SIMD2(1, Float(0.5 + drift(4, swell))),
            SIMD2(0, 1),
            SIMD2(Float(0.5 + drift(5, swell)), 1),
            SIMD2(1, 1),
        ]
    }

    private var colors: [Color] {
        let cpu = Theme.accent(MetricKind.cpu)
        let gpu = Theme.accent(MetricKind.gpu)
        let memory = Theme.accent(MetricKind.memory)
        let base = Color(hue: 0.66, saturation: 0.55, brightness: 0.35)

        // Corners stay dark so the glass tiles keep their contrast; the colour
        // lives in the middle band where the content floats.
        return [
            base.opacity(0.5), cpu.opacity(0.35 + load * 0.3), base.opacity(0.5),
            gpu.opacity(0.3), base.opacity(0.25), memory.opacity(0.28),
            base.opacity(0.5), gpu.opacity(0.32), base.opacity(0.5),
        ]
    }
}

/// Bridges `NSVisualEffectView`, which is still the only way to blur what is
/// behind a window.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}
