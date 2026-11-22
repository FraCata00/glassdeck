import GlassDeckKit
import SwiftUI

/// Top CPU consumers, sampled only while a window that shows them is open.
struct ProcessListView: View {
    let processes: [ProcessSample]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top processes")
                .font(Typography.label)
                .foregroundStyle(.secondary)

            if processes.isEmpty {
                Text("Sampling…")
                    .font(Typography.body)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(processes.enumerated()), id: \.element.id) { index, process in
                    if index > 0 {
                        Divider().opacity(0.35)
                    }
                    HStack(spacing: 8) {
                        Text(process.name)
                            .font(Typography.label)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text(ValueFormatter.bytes(process.memoryBytes))
                            .font(Typography.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(verbatim: "\(ValueFormatter.fixed(process.cpuPercent, places: 1))%")
                            .font(Typography.label)
                            .monospacedDigit()
                            .frame(width: 46, alignment: .trailing)
                    }
                }
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: Theme.tileCornerRadius)
        .animation(.smooth(duration: 0.3), value: processes)
    }
}

extension View {
    /// Keeps the monitor sampling processes while `isEnabled` holds.
    ///
    /// The panel and the dashboard both show the list and can both be open, so
    /// neither may simply switch the monitor's flag off when it goes away — the
    /// monitor counts the interested views instead. Callers pass their window's
    /// visibility in `isEnabled`: closing either window only orders it out, so
    /// a hold tied to `onDisappear` alone went on sampling every process on
    /// every tick for the rest of the session.
    func samplesProcesses(with monitor: SystemMonitor, while isEnabled: Bool) -> some View {
        holds(
            while: isEnabled,
            begin: { monitor.beginSamplingProcesses() },
            end: { monitor.endSamplingProcesses() }
        )
    }
}
