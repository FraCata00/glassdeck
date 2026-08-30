import GlassDeckKit
import SwiftUI

/// The headline element of the dashboard: a ring that fills with the metric's
/// current fraction, with the value stacked in the centre.
struct GaugeRing: View {
    let kind: MetricKind
    let fraction: Double
    var headline: String
    var size: CGFloat = 86
    var lineWidth: CGFloat = 9
    var isSelected = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.primary.opacity(0.09), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.001, fraction.clamped01))
                .stroke(
                    Theme.gradient(kind),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.55), value: fraction)

            VStack(spacing: 1) {
                Text(headline)
                    .font(.system(size: size * 0.215, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(kind.shortTitle)
                    .font(.system(size: size * 0.115, weight: .medium))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
        .accessibilityValue(headline)
    }
}
