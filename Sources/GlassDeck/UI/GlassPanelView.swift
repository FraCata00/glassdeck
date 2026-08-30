import GlassDeckKit
import SwiftUI

/// The menu bar panel: a compact Liquid Glass dashboard.
///
/// Selecting a gauge morphs the detail card below it — the gauges and the card
/// share a `GlassEffectContainer`, which is what produces the fluid merge on macOS 26.
struct GlassPanelView: View {
    @Environment(SystemMonitor.self) private var monitor
    @Environment(Preferences.self) private var preferences
    @Environment(AppModel.self) private var model

    @State private var selection: MetricKind = .cpu
    @Namespace private var glassNamespace

    var body: some View {
        VStack(spacing: 14) {
            header

            GlassStack(spacing: 20) {
                VStack(spacing: 14) {
                    gauges
                    MetricDetailCard(
                        kind: selection,
                        snapshot: monitor.snapshot,
                        history: monitor.history(for: selection)
                    )
                    .glassMorph(id: "detail", in: glassNamespace)
                }
            }

            if preferences.showsProcesses {
                ProcessListView(processes: monitor.topProcesses)
            }

            footer
        }
        .padding(16)
        .frame(width: Theme.panelWidth)
        .task {
            monitor.samplesProcesses = preferences.showsProcesses
            await monitor.refreshNow()
        }
        .onDisappear { monitor.samplesProcesses = false }
        .onChange(of: preferences.showsProcesses) { _, shows in
            monitor.samplesProcesses = shows
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.gradient(.cpu))
            VStack(alignment: .leading, spacing: 0) {
                Text("GlassDeck")
                    .font(.system(size: 13, weight: .semibold))
                Text(SystemIdentity.machineDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(SystemIdentity.uptimeDescription)
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }

    private var gauges: some View {
        HStack(spacing: 10) {
            ForEach(availableMetrics) { kind in
                Button {
                    withAnimation(.smooth(duration: 0.4)) { selection = kind }
                } label: {
                    GaugeRing(
                        kind: kind,
                        fraction: monitor.snapshot.fraction(for: kind),
                        headline: monitor.snapshot.headline(for: kind),
                        size: gaugeSize,
                        lineWidth: 8,
                        isSelected: selection == kind
                    )
                    .padding(6)
                }
                .buttonStyle(.plain)
                .glassSurface(cornerRadius: gaugeSize, interactive: true)
                .glassMorph(id: kind, in: glassNamespace)
                .overlay {
                    if selection == kind {
                        Circle().strokeBorder(Theme.accent(kind).opacity(0.55), lineWidth: 1.2)
                    }
                }
                .help("\(kind.title): \(monitor.snapshot.caption(for: kind))")
            }
        }
    }

    /// Metrics this Mac cannot actually report are hidden rather than shown as "n/a".
    private var availableMetrics: [MetricKind] {
        preferences.dashboardMetrics.filter { monitor.snapshot.supports($0) }
    }

    /// Gauges shrink as more metrics are enabled so the panel keeps its width.
    private var gaugeSize: CGFloat {
        switch availableMetrics.count {
        case ...3: 92
        case 4: 76
        case 5: 66
        default: 56
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                model.showDashboard()
            } label: {
                Label("Dashboard", systemImage: "rectangle.on.rectangle")
                    .font(.system(size: 11, weight: .medium))
            }
            .glassButton(prominent: true)

            Button {
                model.showSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .glassButton()
            .help("Settings")

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .glassButton()
            .help("Quit GlassDeck")
        }
    }
}

/// Small facts about the host that make the panel feel situated.
enum SystemIdentity {
    static let machineDescription: String = {
        let info = ProcessInfo.processInfo
        let version = info.operatingSystemVersion
        return "\(chipName) · macOS \(version.majorVersion).\(version.minorVersion)"
    }()

    static var uptimeDescription: String {
        let uptime = Int(ProcessInfo.processInfo.systemUptime)
        let days = uptime / 86_400
        let hours = (uptime % 86_400) / 3_600
        let minutes = (uptime % 3_600) / 60
        if days > 0 { return String(format: String(localized: "up %1$lldd %2$lldh"), days, hours) }
        if hours > 0 { return String(format: String(localized: "up %1$lldh %2$lldm"), hours, minutes) }
        return String(format: String(localized: "up %lldm"), minutes)
    }

    /// `machdep.cpu.brand_string` is the friendliest name available without IOKit.
    static let chipName: String = {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "Mac" }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }()
}
