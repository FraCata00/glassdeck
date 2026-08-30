import GlassDeckKit
import SwiftUI

/// The full-size window: a blurred, drifting backdrop with the metrics floating
/// over it in Liquid Glass.
struct DashboardView: View {
    @Environment(SystemMonitor.self) private var monitor
    @Environment(Preferences.self) private var preferences
    @Environment(AppModel.self) private var model

    @Namespace private var glass
    @State private var focus: MetricKind = .cpu

    private let columns = [GridItem(.adaptive(minimum: 224), spacing: 14)]

    var body: some View {
        ZStack {
            AuroraBackdrop(snapshot: monitor.snapshot)

            ScrollView {
                GlassStack(spacing: 26) {
                    VStack(spacing: 14) {
                        header
                        hero
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(metrics) { kind in
                                MetricCard(
                                    kind: kind,
                                    snapshot: monitor.snapshot,
                                    history: monitor.history(for: kind),
                                    isFocused: focus == kind
                                )
                                .glassMorph(id: kind, in: glass)
                                .onTapGesture {
                                    withAnimation(.smooth(duration: 0.4)) { focus = kind }
                                }
                            }
                        }
                        if preferences.showsProcesses {
                            ProcessListView(processes: monitor.topProcesses)
                                .glassMorph(id: "processes", in: glass)
                        }
                    }
                    .padding(18)
                }
            }
            .scrollIndicators(.never)
        }
        .background(WindowChrome())
        .frame(minWidth: 560, minHeight: 480)
        .task { await monitor.refreshNow() }
        .samplesProcesses(with: monitor, while: preferences.showsProcesses)
    }

    private var metrics: [MetricKind] {
        preferences.dashboardMetrics.filter { monitor.snapshot.supports($0) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            // Leaves room for the traffic lights, which sit over the content in
            // a full-size-content-view window.
            Spacer().frame(width: 62)

            VStack(alignment: .leading, spacing: 1) {
                Text("GlassDeck")
                    .font(.system(size: 13, weight: .semibold))
                Text(SystemIdentity.machineDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(SystemIdentity.uptimeDescription, systemImage: "clock")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button {
                model.showSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
            }
            .glassButton()
            .help("Settings")
        }
        .padding(.bottom, 2)
    }

    private var hero: some View {
        HStack(spacing: 14) {
            VStack(spacing: 10) {
                GaugeRing(
                    kind: focus,
                    fraction: monitor.snapshot.fraction(for: focus),
                    headline: monitor.snapshot.headline(for: focus),
                    size: 124,
                    lineWidth: 12,
                    isSelected: true
                )
                Text(monitor.snapshot.caption(for: focus))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(18)
            .frame(minWidth: 190)
            .glassSurface(cornerRadius: Theme.cornerRadius)
            .glassMorph(id: "hero", in: glass)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(SystemIdentity.chipName)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if let load = monitor.snapshot.cpu.loadAverage.first {
                        Text("load \(ValueFormatter.decimal(load))")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                CoreGridView(cpu: monitor.snapshot.cpu)

                Sparkline(values: monitor.history(for: focus), gradient: Theme.gradient(focus))
                    .frame(height: 46)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .glassSurface(cornerRadius: Theme.cornerRadius)
            .glassMorph(id: "cores", in: glass)
        }
    }
}

/// One metric, laid out the way macOS lays out its own tiles: an icon chip and
/// a quiet label on top, the number as the hero, then the trend and the level.
private struct MetricCard: View {
    let kind: MetricKind
    let snapshot: MetricsSnapshot
    let history: [Double]
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                iconChip
                Text(kind.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                statusDot
            }

            Text(snapshot.headline(for: kind))
                .font(.system(size: 28, weight: .medium))
                .monospacedDigit()
                .contentTransition(.numericText())
                .padding(.top, 10)

            Text(snapshot.caption(for: kind))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.top, 1)

            Sparkline(values: history, gradient: Theme.gradient(kind))
                .frame(height: 38)
                .padding(.top, 12)

            // The sparkline carries the trend; this carries where the metric
            // stands right now.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.09))
                    Capsule()
                        .fill(Theme.accent(kind))
                        .frame(width: max(3, proxy.size.width * snapshot.fraction(for: kind).clamped01))
                        .animation(.smooth(duration: 0.5), value: snapshot.fraction(for: kind))
                }
            }
            .frame(height: 3)
            .padding(.top, 10)
        }
        .padding(16)
        .glassSurface(cornerRadius: Theme.cornerRadius, interactive: true)
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.accent(kind).opacity(0.45), lineWidth: 1)
            }
        }
    }

    private var iconChip: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.iconChip(kind))
            .frame(width: 22, height: 22)
            .overlay {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent(kind))
            }
    }

    private var statusDot: some View {
        Circle()
            .fill(Theme.statusTint(snapshot.fraction(for: kind)))
            .frame(width: 5, height: 5)
            .opacity(snapshot.fraction(for: kind) > 0.7 ? 1 : 0.35)
    }
}

/// Strips the window down to a floating glass panel: no titlebar, no opaque
/// background, draggable from anywhere.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
