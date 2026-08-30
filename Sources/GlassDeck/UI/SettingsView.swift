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

    @State private var launchesAtLogin = LoginItem.isEnabled

    var body: some View {
        @Bindable var preferences = preferences

        TabView {
            general(preferences: $preferences)
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }
            metrics(preferences: $preferences)
                .tabItem { Label("Metrics", systemImage: "chart.bar") }
            touchBarSettings(preferences: $preferences)
                .tabItem { Label("Touch Bar", systemImage: "macbook.gen1") }
        }
        .frame(width: 460, height: 330)
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
    }

    private func metrics(preferences: Bindable<Preferences>) -> some View {
        Form {
            Section("Shown in the panel and dashboard") {
                ForEach(MetricKind.allCases) { kind in
                    Toggle(isOn: binding(for: kind, keyPath: \.dashboardMetrics)) {
                        Label(kind.title, systemImage: kind.symbolName)
                    }
                }
            }
        }
        .formStyle(.grouped)
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
                ForEach(MetricKind.allCases) { kind in
                    Toggle(isOn: binding(for: kind, keyPath: \.touchBarMetrics)) {
                        Label(kind.title, systemImage: kind.symbolName)
                    }
                }
            }

        }
        .formStyle(.grouped)
    }

    /// Metrics this machine reports. Before the first sample nothing
    /// hardware-dependent is known yet, so the full list stands in.
    private var reportableMetrics: [MetricKind] {
        guard monitor.snapshot != .empty else { return MetricKind.allCases }
        return MetricKind.allCases.filter { monitor.snapshot.supports($0) }
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
