import AppKit
import Combine
import GlassDeckKit
import SwiftUI

/// Settings window: sampling cadence, which metrics appear where, and the
/// Touch Bar / login-item switches.
struct SettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(TouchBarController.self) private var touchBar
    @Environment(SystemMonitor.self) private var monitor
    @Environment(ClockTicker.self) private var clock

    @State private var launchesAtLogin = LoginItem.isEnabled
    @State private var isOnScreen = true
    @State private var lastSnapshot: MetricsSnapshot = .empty

    var body: some View {
        @Bindable var preferences = preferences

        TabView {
            general(preferences: $preferences)
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }
            metrics(preferences: $preferences)
                .tabItem { Label("Metrics", systemImage: "chart.bar") }
            modules(preferences: $preferences)
                .tabItem { Label("Modules", systemImage: "square.grid.2x2") }
            touchBarSettings(preferences: $preferences)
                .tabItem { Label("Touch Bar", systemImage: "macbook.gen1") }
        }
        .frame(width: 460, height: 330)
        // The window outlives its closing — `isReleasedWhenClosed` is false — so
        // the gate the panel and the dashboard need applies here too.
        .tracksVisibility($isOnScreen) { lastSnapshot = monitor.snapshot }
    }

    private func general(preferences: Bindable<Preferences>) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Slider(value: preferences.refreshInterval, in: 0.5...5, step: 0.5) {
                        Text("Refresh interval")
                    } minimumValueLabel: {
                        Text("0.5s").font(.caption2)
                    } maximumValueLabel: {
                        Text("5s").font(.caption2)
                    }
                    Text("Sampling every \(ValueFormatter.seconds(preferences.wrappedValue.refreshInterval))s. Lower is snappier, higher is kinder to the battery.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Menu bar", selection: preferences.menuBarStyle) {
                    ForEach(Preferences.MenuBarStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                // Only what this Mac can actually report: offering "Fans" on a
                // fanless Mac just pins the status item to n/a.
                Picker("Menu bar metric", selection: preferences.menuBarMetric) {
                    ForEach(reportableMetrics) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .disabled(preferences.wrappedValue.menuBarStyle == .graph)

                Toggle("Show top processes", isOn: preferences.showsProcesses)

                if snapshot.supports(.temperature) {
                    Toggle("Warn when the Mac runs hot", isOn: Binding(
                        get: { preferences.wrappedValue.isTemperatureAlertEnabled },
                        set: { enabled in
                            preferences.wrappedValue.isTemperatureAlertEnabled = enabled
                            // Permission is asked for only when it is turned on.
                            if enabled { ThresholdAlerts.requestAuthorization() }
                        }
                    ))

                    if preferences.wrappedValue.isTemperatureAlertEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Slider(value: preferences.temperatureThreshold, in: 60...100, step: 5) {
                                Text("Warn above")
                            } minimumValueLabel: {
                                Text("60°C").font(.caption2)
                            } maximumValueLabel: {
                                Text("100°C").font(.caption2)
                            }
                            Text("A notification once the hottest sensor passes \(Int(preferences.wrappedValue.temperatureThreshold))°C, and not again until it has cooled down.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Written through a binding rather than `onChange` so that only
                // the user's own taps register the login item: refreshing the
                // toggle from the system below must not write back.
                Toggle("Open at login", isOn: Binding(
                    get: { launchesAtLogin },
                    set: { wanted in
                        launchesAtLogin = LoginItem.setEnabled(wanted) ? wanted : LoginItem.isEnabled
                    }
                ))
                // The switch also lives in System Settings, so the window can be
                // sitting on a stale answer by the time it is looked at again.
                .onAppear { launchesAtLogin = LoginItem.isEnabled }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    launchesAtLogin = LoginItem.isEnabled
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.glass)
    }

    /// A `List` rather than a `Form`, because rows have to be draggable and only
    /// a list carries `onMove` on macOS.
    private func metrics(preferences: Bindable<Preferences>) -> some View {
        List {
            Section {
                ForEach(preferences.wrappedValue.metricOrder) { kind in
                    Toggle(isOn: binding(for: kind, keyPath: \.dashboardMetrics)) {
                        Label(kind.title, systemImage: kind.symbolName)
                    }
                }
                .onMove { self.preferences.moveMetrics(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Shown in the panel and dashboard")
            } footer: {
                Text("Drag to reorder. The order is shared by the panel, the Touch Bar and the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // A list renders toggles as checkboxes by default, which would not match
        // the switches in the other tabs.
        .toggleStyle(.glass)
    }

    /// The two cards that are not a gauge: the paired devices' batteries, and
    /// the wall of clocks. A `List` for the same reason as the metrics tab —
    /// the time zones are reorderable.
    private func modules(preferences: Bindable<Preferences>) -> some View {
        List {
            Section {
                Toggle(isOn: moduleBinding(.bluetooth)) {
                    Label(ModuleKind.bluetooth.title, systemImage: ModuleKind.bluetooth.symbolName)
                }
                Text("The charge of every paired device that reports one. A device that is not connected keeps publishing the level it was last seen at, so those rows are dimmed and marked rather than hidden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Only once the module is on: with it off nothing is sampled,
                // so "nothing is reporting" would be true of every Mac.
                if preferences.wrappedValue.panelModules.contains(.bluetooth),
                   !snapshot.bluetooth.isAvailable {
                    Label("Nothing paired is reporting a battery level right now.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("macOS asks for permission the first time this is switched on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: moduleBinding(.clock)) {
                    Label(ModuleKind.clock.title, systemImage: ModuleKind.clock.symbolName)
                }

                ForEach(preferences.wrappedValue.clockZones) { zone in
                    zoneRow(zone)
                }
                .onMove { self.preferences.moveClockZones(fromOffsets: $0, toOffset: $1) }

                Menu {
                    ForEach(Self.zoneRegions, id: \.name) { region in
                        Menu(region.name) {
                            ForEach(region.identifiers, id: \.self) { identifier in
                                Button(ClockZone.cityName(for: identifier)) {
                                    self.preferences.addClockZone(identifier)
                                }
                            }
                        }
                    }
                } label: {
                    Label("Add a time zone", systemImage: "plus")
                }

                Picker("Show in the menu bar", selection: menuBarZoneBinding) {
                    Text("Off").tag(String?.none)
                    ForEach(preferences.wrappedValue.clockZones) { zone in
                        Text(zone.displayLabel).tag(String?.some(zone.identifier))
                    }
                }
                .disabled(preferences.wrappedValue.clockZones.isEmpty)
            } footer: {
                Text("Rename a row to whatever the clock is for. Drag to reorder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.glass)
        // The rows preview a live time, and the ticker is otherwise asleep until
        // the module is switched on.
        .onAppear { clock.beginObserving() }
        .onDisappear { clock.endObserving() }
    }

    private func zoneRow(_ zone: ClockZone) -> some View {
        HStack(spacing: 8) {
            TextField(
                ClockZone.cityName(for: zone.identifier),
                text: Binding(
                    get: { zone.label },
                    set: { preferences.renameClockZone(zone.identifier, to: $0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 150)

            Text(zone.identifier)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)

            Spacer(minLength: 4)

            if let timeZone = zone.timeZone {
                Text(WorldClock.time(in: timeZone, at: clock.now))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Button {
                if let index = preferences.clockZones.firstIndex(of: zone) {
                    preferences.removeClockZones(atOffsets: IndexSet(integer: index))
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove this time zone")
        }
    }

    /// Every zone macOS knows, grouped by region for the add menu.
    ///
    /// Built once: there are some six hundred identifiers, and this is read
    /// every time the settings body runs.
    private static let zoneRegions: [(name: String, identifiers: [String])] = {
        Dictionary(grouping: TimeZone.knownTimeZoneIdentifiers, by: ClockZone.region(for:))
            .map { region in
                (
                    name: region.key,
                    identifiers: region.value.sorted {
                        ClockZone.cityName(for: $0) < ClockZone.cityName(for: $1)
                    }
                )
            }
            .sorted { $0.name < $1.name }
    }()

    private var menuBarZoneBinding: Binding<String?> {
        Binding(
            get: { preferences.menuBarClockZone },
            set: { preferences.menuBarClockZone = $0 }
        )
    }

    private func moduleBinding(_ module: ModuleKind) -> Binding<Bool> {
        Binding(
            get: { preferences.panelModules.contains(module) },
            set: { _ in preferences.toggle(module) }
        )
    }

    private func touchBarSettings(preferences: Bindable<Preferences>) -> some View {
        Form {
            Section {
                Toggle("Show GlassDeck on the Touch Bar", isOn: preferences.isTouchBarEnabled)
                Picker("Placement", selection: preferences.touchBarPresentation) {
                    ForEach(Preferences.TouchBarPresentation.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .disabled(!preferences.wrappedValue.isTouchBarEnabled)
                Picker("Position", selection: preferences.touchBarAlignment) {
                    ForEach(Preferences.TouchBarAlignment.allCases) { alignment in
                        Text(alignment.title).tag(alignment)
                    }
                }
                .disabled(!preferences.wrappedValue.isTouchBarEnabled)
                Text(preferences.wrappedValue.touchBarPresentation.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("The shrink button steps down through full width, the compact bar and a small meter; only a tap on the smallest one hands the Touch Bar back, and the Control Strip meter brings it straight back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !touchBar.isSupported {
                    Label(
                        "No Touch Bar detected on this Mac. The setting is kept for when GlassDeck runs on one.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Section("Metrics in the Touch Bar strip") {
                ForEach(preferences.wrappedValue.metricOrder) { kind in
                    Toggle(isOn: binding(for: kind, keyPath: \.touchBarMetrics)) {
                        Label(kind.title, systemImage: kind.symbolName)
                    }
                }
            }

        }
        .formStyle(.grouped)
        .toggleStyle(.glass)
    }

    /// The reading the settings draw from: the live one while the window is on
    /// screen, the last one it saw once it is not.
    ///
    /// Only three rows depend on it — which metrics this Mac can report, the
    /// temperature switch, the Bluetooth notice — but reading it at all is what
    /// invalidates the body, and the body is a four-tab `Form` whose relayout
    /// costs far more than the rows that asked for the value.
    private var snapshot: MetricsSnapshot {
        isOnScreen ? monitor.snapshot : lastSnapshot
    }

    /// Metrics this machine reports. Before the first sample nothing
    /// hardware-dependent is known yet, so the full list stands in.
    private var reportableMetrics: [MetricKind] {
        guard snapshot != .empty else { return MetricKind.allCases }
        return MetricKind.allCases.filter { snapshot.supports($0) }
    }

    private func binding(
        for kind: MetricKind,
        keyPath: ReferenceWritableKeyPath<Preferences, [MetricKind]>
    ) -> Binding<Bool> {
        Binding(
            get: { preferences[keyPath: keyPath].contains(kind) },
            set: { _ in preferences.toggle(kind, in: keyPath) }
        )
    }
}
