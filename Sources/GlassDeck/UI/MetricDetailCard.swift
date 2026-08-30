import GlassDeckKit
import SwiftUI

/// The expanded view of whichever metric is selected: history curve plus the
/// two or three numbers that actually matter for that metric.
struct MetricDetailCard: View {
    let kind: MetricKind
    let snapshot: MetricsSnapshot
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(kind.title, systemImage: kind.symbolName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(snapshot.headline(for: kind))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Sparkline(values: history, gradient: Theme.gradient(kind))
                .frame(height: 44)

            HStack(spacing: 14) {
                ForEach(snapshot.details(for: kind)) { detail in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(detail.value)
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                        Text(detail.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if detail.id != snapshot.details(for: kind).last?.id { Spacer(minLength: 0) }
                }
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: Theme.tileCornerRadius)
    }
}
