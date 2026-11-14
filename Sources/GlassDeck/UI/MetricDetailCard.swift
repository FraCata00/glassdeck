import GlassDeckKit
import SwiftUI

/// The expanded view of whichever metric is selected: history curve plus the
/// two or three numbers that actually matter for that metric.
struct MetricDetailCard: View {
    let kind: MetricKind
    let snapshot: MetricsSnapshot
    let history: [Double]

    var body: some View {
        // Computed once: `details(for:)` builds and formats the whole array, and
        // the row loop used to ask for it again for every item plus once more to
        // find the last one.
        let details = snapshot.details(for: kind)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(kind.title, systemImage: kind.symbolName)
                    .font(Typography.heading)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(snapshot.headline(for: kind))
                    .font(Typography.value)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Sparkline(values: history, gradient: Theme.gradient(kind), accent: Theme.accent(kind))
                .frame(height: 44)

            HStack(spacing: 14) {
                ForEach(details) { detail in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(detail.value)
                            .font(Typography.heading)
                            .monospacedDigit()
                        Text(detail.label)
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    if detail.id != details.last?.id { Spacer(minLength: 0) }
                }
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: Theme.tileCornerRadius)
    }
}
