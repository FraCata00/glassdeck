import GlassDeckKit
import SwiftUI

/// The window's depth: the desktop blurred behind the glass, with a slow colour
/// field drifting over it.
///
/// The field is driven by the sampling tick rather than by a display-link
/// animation — a system monitor that burns CPU on its own decoration would be
/// self-defeating — and its colours lean towards whichever metric is busiest.
///
/// It moves in steps and rests between them. Eased on every sample, each move
/// outlasted the gap to the next one, so the window never stopped rendering
/// for as long as it was open; stepped, it renders for `easing` seconds out of
/// every `stepInterval` and is still the rest of the time.
struct AuroraBackdrop: View {
    let snapshot: MetricsSnapshot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds between two moves of the field.
    private static let stepInterval: TimeInterval = 8
    /// How long one move is eased over. Under the step interval, so the field
    /// comes to rest before it moves again.
    private static let easing: TimeInterval = 3.2
    /// How finely the swell follows the load: a quarter at a time, so a busy
    /// moment shows and the noise between samples does not.
    private static let loadSteps = 4.0

    /// What the field is drawn from. Both halves change only on a step, so
    /// nothing redraws the field between two of them.
    private struct Pose: Equatable {
        let phase: Double
        let load: Double
    }

    /// The field holds still when the user has asked for less motion, and in
    /// Low Power Mode, where even a few seconds of easing in every eight are
    /// rendering nobody asked for.
    private var isStill: Bool {
        reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blending: .behindWindow)

            // No blur: a 3 × 3 mesh is already as soft as a gradient gets, and
            // a 70 pt blur over the whole window was the costliest thing in
            // its every frame. A little less opacity makes up for the edges.
            MeshGradient(width: 3, height: 3, points: points, colors: colors)
                .opacity(0.45)
                .animation(isStill ? nil : .smooth(duration: Self.easing), value: pose)
                .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
    }

    private var pose: Pose { Pose(phase: phase, load: load) }

    /// Advances once a step, at the same average pace as before: about that of
    /// a lava lamp.
    private var phase: Double {
        guard !isStill else { return 0 }
        let step = (snapshot.timestamp.timeIntervalSinceReferenceDate / Self.stepInterval).rounded(.down)
        return step * Self.stepInterval / 14
    }

    /// The hottest metric decides how far the field swells.
    ///
    /// Held at a fixed swell while still, or the field would jump — unanimated —
    /// with every sample instead of resting.
    private var load: Double {
        guard !isStill else { return 0.25 }
        let load = max(snapshot.cpu.total, snapshot.gpu.utilisation).clamped01
        return (load * Self.loadSteps).rounded() / Self.loadSteps
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
