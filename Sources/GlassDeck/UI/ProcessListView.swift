import GlassDeckKit
import SwiftUI

/// Top CPU consumers, sampled only while a window that shows them is open.
struct ProcessListView: View {
    let processes: [ProcessSample]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top processes")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            if processes.isEmpty {
                Text("Sampling…")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(processes.enumerated()), id: \.element.id) { index, process in
                    if index > 0 {
                        Divider().opacity(0.35)
                    }
                    HStack(spacing: 8) {
                        Text(process.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text(ValueFormatter.bytes(process.memoryBytes))
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f%%", process.cpuPercent))
                            .font(.system(size: 11, weight: .medium))
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

/// Ties process sampling to a view's time on screen.
///
/// The panel and the dashboard both show the list and can both be open, so
/// neither may simply switch the monitor's flag off when it goes away — the
/// monitor counts the interested views instead.
private struct ProcessSamplingLifetime: ViewModifier {
    let monitor: SystemMonitor
    let isEnabled: Bool

    @State private var isRegistered = false

    func body(content: Content) -> some View {
        content
            .onAppear { register(isEnabled) }
            .onDisappear { register(false) }
            .onChange(of: isEnabled) { _, wanted in register(wanted) }
    }

    /// Idempotent, so a repeated `onAppear` cannot register the same view twice.
    private func register(_ wanted: Bool) {
        guard wanted != isRegistered else { return }
        isRegistered = wanted
        if wanted { monitor.beginSamplingProcesses() } else { monitor.endSamplingProcesses() }
    }
}

extension View {
    func samplesProcesses(with monitor: SystemMonitor, while isEnabled: Bool) -> some View {
        modifier(ProcessSamplingLifetime(monitor: monitor, isEnabled: isEnabled))
    }
}
