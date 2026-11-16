import GlassDeckKit
import SwiftUI

/// Per-core load bars, grouped into the performance and efficiency clusters that
/// Apple silicon exposes. On Intel Macs the whole set renders as one group.
struct CoreGridView: View {
    let cpu: CPUUsage

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if let performance = clusters.performance {
                cluster(title: "P", loads: performance)
            }
            if let efficiency = clusters.efficiency {
                cluster(title: "E", loads: efficiency)
            }
            if clusters.performance == nil, clusters.efficiency == nil {
                cluster(title: "Cores", loads: cpu.perCore)
            }
        }
    }

    /// Taken from the kit rather than sliced here: the cores are not numbered
    /// performance first, so a prefix/suffix split put the clusters' bars
    /// under each other's labels.
    private var clusters: (performance: [Double]?, efficiency: [Double]?) {
        (cpu.performanceCoreLoads, cpu.efficiencyCoreLoads)
    }

    private func cluster(title: String, loads: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(loads.enumerated()), id: \.offset) { _, load in
                    Capsule()
                        .fill(.primary.opacity(0.08))
                        .frame(width: 7, height: 26)
                        .overlay(alignment: .bottom) {
                            Capsule()
                                .fill(Theme.gradient(MetricKind.cpu))
                                .frame(width: 7, height: max(2, 26 * load.clamped01))
                                .animation(.smooth(duration: 0.45), value: load)
                        }
                }
            }
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        }
    }
}
