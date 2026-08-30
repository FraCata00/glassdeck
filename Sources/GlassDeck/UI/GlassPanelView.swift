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

    private static let panelPadding: CGFloat = 16
    private static let gaugeSpacing: CGFloat = 10
    /// Breathing room drawn around each ring, inside its own glass surface.
    private static let gaugePadding: CGFloat = 6
    /// Below this a ring's value stops being readable at a glance.
    private static let minimumGaugeSize: CGFloat = 56
    /// Above this a lone gauge is just a large circle in a 396 pt panel.
    private static let maximumGaugeSize: CGFloat = 110

    private static var usableWidth: CGFloat { Theme.panelWidth - panelPadding * 2 }

    /// The gauge size that makes a row of `count` fill the panel exactly.
    private static func fillingSize(forRowOf count: Int) -> CGFloat {
        let count = CGFloat(max(count, 1))
        return (usableWidth - gaugeSpacing * (count - 1)) / count - gaugePadding * 2
    }

    /// The most gauges that fit on one row while each stays legible.
    private static let maximumPerRow: Int = {
        var count = 1
        while fillingSize(forRowOf: count + 1) >= minimumGaugeSize { count += 1 }
        return count
    }()

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
        .padding(Self.panelPadding)
        .frame(width: Theme.panelWidth)
        .task { await monitor.refreshNow() }
        .samplesProcesses(with: monitor, while: preferences.showsProcesses)
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
        VStack(spacing: Self.gaugeSpacing) {
            ForEach(Array(gaugeRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Self.gaugeSpacing) {
                    ForEach(row) { gauge(for: $0) }
                }
                // A last row with fewer gauges sits centred rather than adrift
                // against the left edge.
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func gauge(for kind: MetricKind) -> some View {
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
            .padding(Self.gaugePadding)
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

    /// Metrics this Mac cannot actually report are hidden rather than shown as "n/a".
    private var availableMetrics: [MetricKind] {
        preferences.dashboardMetrics.filter { monitor.snapshot.supports($0) }
    }

    /// Gauges are sized to fill the row they sit on rather than picked from a
    /// ladder of fixed sizes, so enabling or disabling a metric resizes the rest
    /// instead of leaving a wider or narrower gap beside them.
    ///
    /// `GaugeRing` has a fixed frame and does not compress, so a row that does
    /// not fit draws past the edge of the panel: the count per row is capped at
    /// what still leaves each ring legible, and the rest wrap.
    private var gaugeSize: CGFloat {
        let perRow = min(max(availableMetrics.count, 1), Self.maximumPerRow)
        return min(Self.fillingSize(forRowOf: perRow), Self.maximumGaugeSize)
    }

    /// The gauges split into full rows, with whatever is left over on the last.
    private var gaugeRows: [[MetricKind]] {
        let metrics = availableMetrics
        guard !metrics.isEmpty else { return [] }

        let perRow = min(metrics.count, Self.maximumPerRow)
        return stride(from: 0, to: metrics.count, by: perRow).map {
            Array(metrics[$0..<min($0 + perRow, metrics.count)])
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
