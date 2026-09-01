import AppKit
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
    @State private var contentHeight: CGFloat = 0
    @State private var isOnScreen = true
    @State private var lastSnapshot: MetricsSnapshot = .empty
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

    /// How tall the panel may grow before it starts scrolling. Measured against
    /// the screen the menu bar is on, less the room the bar itself takes.
    private static var maximumPanelHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return max(420, screen - 40)
    }

    /// The gauge size that makes a row of `count` fill the panel exactly.
    private static func fillingSize(forRowOf count: Int) -> CGFloat {
        let count = CGFloat(max(count, 1))
        return (usableWidth - gaugeSpacing * (count - 1)) / count - gaugePadding * 2
    }

    private static func rowWidth(of count: Int, size: CGFloat) -> CGFloat {
        CGFloat(count) * (size + gaugePadding * 2) + CGFloat(count - 1) * gaugeSpacing
    }

    /// The split that leaves the least of the panel's width unused.
    ///
    /// The gauges are circles of a single size, so for some counts no split
    /// fills every row: five come out as 3 · 2. Rather than guess a rule, every
    /// split that keeps the rings legible is measured and the fullest wins, with
    /// fewer rows breaking a tie. Deriving the size from the row count is the
    /// whole point — sizing for the widest row a split allows is what left nine
    /// metrics as 4 · 4 · 1 with three quarters of the last row empty.
    private static func layout(for count: Int) -> (perRow: Int, size: CGFloat) {
        guard count > 0 else { return (1, maximumGaugeSize) }

        var best: (perRow: Int, size: CGFloat, fill: CGFloat, rows: Int)?
        for rows in 1...count {
            let perRow = Int((Double(count) / Double(rows)).rounded(.up))
            let exact = fillingSize(forRowOf: perRow)
            guard exact >= minimumGaugeSize else { continue }
            let size = min(exact, maximumGaugeSize)

            let counts = stride(from: 0, to: count, by: perRow).map { min(perRow, count - $0) }
            let used = counts.reduce(CGFloat(0)) { $0 + rowWidth(of: $1, size: size) }
            let fill = used / (CGFloat(counts.count) * usableWidth)

            let isBetter = best.map { fill > $0.fill || (fill == $0.fill && counts.count < $0.rows) } ?? true
            if isBetter { best = (perRow, size, fill, counts.count) }
        }

        // A row of one is always legible, so there is always a winner.
        return best.map { ($0.perRow, $0.size) } ?? (1, maximumGaugeSize)
    }

    var body: some View {
        // Every metric enabled, with the process list, runs past 800 pt. The
        // panel used to be exactly as tall as its content and simply lost the
        // bottom of itself on a short screen, with no way to reach it.
        ScrollView {
            VStack(spacing: 14) {
                header

                GlassStack(spacing: 20) {
                    VStack(spacing: 14) {
                        gauges
                        MetricDetailCard(
                            kind: selectedMetric,
                            snapshot: snapshot,
                            history: history(for: selectedMetric)
                        )
                        .glassMorph(id: "detail", in: glassNamespace)
                    }
                }

                if preferences.showsProcesses {
                    ProcessListView(processes: processes)
                }

                footer
            }
            .padding(Self.panelPadding)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Theme.panelWidth)
        // Measured rather than capped with `maxHeight`: a scroll view is greedy
        // in its axis, so a maximum would have made every panel that tall and
        // left a short one mostly empty. This is the content's own height until
        // it outgrows the screen, and the cap only after that.
        .frame(height: min(max(contentHeight, 1), Self.maximumPanelHeight))
        .task { await monitor.refreshNow() }
        .samplesProcesses(with: monitor, while: preferences.showsProcesses)
        // Closing the panel does not tear this tree down, so what it reads has
        // to be switched off by hand or it animates on into a hidden window.
        .tracksVisibility($isOnScreen) { lastSnapshot = monitor.snapshot }
    }

    /// The reading the panel draws: the live one while it is on screen, the last
    /// one it saw once it is not.
    private var snapshot: MetricsSnapshot {
        isOnScreen ? monitor.snapshot : lastSnapshot
    }

    private func history(for kind: MetricKind) -> [Double] {
        isOnScreen ? monitor.history(for: kind) : []
    }

    private var processes: [ProcessSample] {
        isOnScreen ? monitor.topProcesses : []
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
                fraction: snapshot.fraction(for: kind),
                headline: snapshot.headline(for: kind),
                size: gaugeSize,
                lineWidth: 8,
                isSelected: selectedMetric == kind
            )
            .padding(Self.gaugePadding)
        }
        .buttonStyle(.plain)
        .glassSurface(cornerRadius: gaugeSize, interactive: true)
        .glassMorph(id: kind, in: glassNamespace)
        .overlay {
            if selectedMetric == kind {
                Circle().strokeBorder(Theme.accent(kind).opacity(0.55), lineWidth: 1.2)
            }
        }
        .help("\(kind.title): \(snapshot.caption(for: kind))")
    }

    /// Metrics this Mac cannot actually report are hidden rather than shown as "n/a".
    private var availableMetrics: [MetricKind] {
        preferences.dashboardMetrics.filter { snapshot.supports($0) }
    }

    /// The metric the detail card shows.
    ///
    /// Resolved rather than stored: turning off whichever metric was selected
    /// used to leave the card describing a gauge that is no longer on screen,
    /// and a first run with CPU disabled opened on CPU regardless.
    private var selectedMetric: MetricKind {
        availableMetrics.contains(selection) ? selection : (availableMetrics.first ?? .cpu)
    }

    /// Gauges are sized to fill the row they sit on rather than picked from a
    /// ladder of fixed sizes, so enabling or disabling a metric resizes the rest
    /// instead of leaving a wider or narrower gap beside them.
    private var gaugeSize: CGFloat {
        Self.layout(for: availableMetrics.count).size
    }

    private var gaugeRows: [[MetricKind]] {
        let metrics = availableMetrics
        guard !metrics.isEmpty else { return [] }

        let perRow = Self.layout(for: metrics.count).perRow
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
