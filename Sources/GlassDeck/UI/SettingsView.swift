import AppKit
import Combine
import GlassDeckKit
import SwiftUI

/// The pages of the settings window, in sidebar order.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case menuBar
    case touchBar
    case panel
    case alerts
    case bluetooth
    case clocks

    var id: String { rawValue }

    /// The sidebar's three runs of pages, set apart by space rather than by
    /// headings, the way System Settings groups its own.
    static let groups: [[SettingsPage]] = [
        [.general, .menuBar, .touchBar],
        [.panel, .alerts],
        [.bluetooth, .clocks],
    ]

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .menuBar: String(localized: "Menu bar")
        case .touchBar: String(localized: "Touch Bar")
        case .panel: String(localized: "Panel and dashboard")
        case .alerts: String(localized: "Alerts")
        case .bluetooth: ModuleKind.bluetooth.title
        case .clocks: ModuleKind.clock.title
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .menuBar: "menubar.rectangle"
        case .touchBar: "rectangle.and.hand.point.up.left.fill"
        case .panel: "square.grid.2x2.fill"
        case .alerts: "bell.badge.fill"
        case .bluetooth: ModuleKind.bluetooth.symbolName
        case .clocks: ModuleKind.clock.symbolName
        }
    }

    /// The colour of the page's icon tile.
    var tint: Color {
        switch self {
        case .general: .gray
        case .menuBar: .blue
        case .touchBar: .indigo
        case .panel: .teal
        case .alerts: .red
        case .bluetooth: .blue
        case .clocks: .orange
        }
    }

    /// The sentence under the page's title.
    var summary: Text {
        switch self {
        case .general: Text("How often GlassDeck samples and how it starts. Nothing here uses the network.")
        case .menuBar: Text("What the icon in the menu bar shows. It is redrawn only when the label would actually look different.")
        case .touchBar: Text("How GlassDeck is drawn on the Touch Bar, where it sits, and which metrics it shows.")
        case .panel: Text("The metrics in the panel and the dashboard. The order set here is shared by every surface.")
        case .alerts: Text("Notifications when something needs attention. They read the slow reading, at most every two seconds.")
        case .bluetooth: Text("The charge of every paired device that reports one. A device that is not connected keeps publishing the level it was last seen at, so those rows are dimmed and marked rather than hidden.")
        case .clocks: Text("Rename a row to whatever the clock is for. Drag to reorder.")
        }
    }

    /// Words the search field also matches, beyond the page's title: the
    /// names of the settings on it.
    var keywords: [String] {
        switch self {
        case .general: [String(localized: "Refresh interval"), String(localized: "Open at login")]
        case .menuBar: [String(localized: "Menu bar metric"), String(localized: "Real-time menu bar")]
        case .touchBar: [String(localized: "Style"), String(localized: "Placement"), String(localized: "Hand-over shortcut")]
        case .panel: [String(localized: "Metrics"), String(localized: "Show top processes")]
        case .alerts: [String(localized: "Warn when the Mac runs hot"), String(localized: "Warn when memory runs short")]
        case .bluetooth: []
        case .clocks: [String(localized: "Add a time zone")]
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return ([title] + keywords).contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

/// Settings window, laid out the way System Settings is: a searchable sidebar
/// of pages beside grouped forms.
///
/// Built from the system's own containers and controls rather than drawn by
/// hand, so that on macOS 26 the sidebar floats as Liquid Glass and every
/// switch, menu and slider is the current system control — and on macOS 15
/// the same window is simply the earlier look, with nothing to fall back from.
struct SettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(TouchBarController.self) private var touchBar
    @Environment(SystemMonitor.self) private var monitor
    @Environment(ClockTicker.self) private var clock

    @State private var page: SettingsPage
    /// The pages visited before and after the current one, for the toolbar's
    /// back and forward buttons.
    @State private var back: [SettingsPage] = []
    @State private var forward: [SettingsPage] = []
    @State private var query = ""
    @State private var launchesAtLogin = LoginItem.isEnabled
    @State private var live = LiveReadings()

    init(page: SettingsPage = .general) {
        _page = State(initialValue: page)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            Form {
                header(page)
                content(page)
            }
            .formStyle(.grouped)
            .id(page)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button { step(from: &back, to: &forward) } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .disabled(back.isEmpty)
                    Button { step(from: &forward, to: &back) } label: {
                        Label("Forward", systemImage: "chevron.right")
                    }
                    .disabled(forward.isEmpty)
                }
            }
        }
        .background(WindowTitle(title: page.title))
        .toggleStyle(.switch)
        .frame(minWidth: SettingsMetrics.minimumSize.width, minHeight: SettingsMetrics.minimumSize.height)
        // The window outlives its closing — `isReleasedWhenClosed` is false — so
        // the gate the panel and the dashboard need applies here too.
        .tracksVisibility($live, monitor: monitor, clock: clock)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: selection) {
            ForEach(SettingsPage.groups.indices, id: \.self) { index in
                Section {
                    ForEach(SettingsPage.groups[index].filter { $0.matches(query) }) { item in
                        Label {
                            Text(item.title)
                        } icon: {
                            SettingsIcon(page: item, size: 20)
                        }
                        .tag(item)
                    }
                }
            }
        }
        .searchable(text: $query, placement: .sidebar, prompt: Text("Search settings"))
        .frame(minWidth: SettingsMetrics.sidebarWidth)
        .navigationSplitViewColumnWidth(SettingsMetrics.sidebarWidth)
        .toolbar(removing: .sidebarToggle)
    }

    /// The sidebar's selection. Choosing a page records the one left behind,
    /// as a browser does, and forgets the pages that were ahead of it.
    private var selection: Binding<SettingsPage?> {
        Binding(
            get: { page },
            set: { chosen in
                guard let chosen, chosen != page else { return }
                back.append(page)
                forward.removeAll()
                page = chosen
            }
        )
    }

    /// Moves one page through the history: the current page goes on `other`,
    /// and the last one on `stack` becomes current.
    private func step(from stack: inout [SettingsPage], to other: inout [SettingsPage]) {
        guard let next = stack.popLast() else { return }
        other.append(page)
        page = next
    }

    // MARK: - Pages

    /// The large icon, the title and what the page is for, at the head of
    /// every page as System Settings has it.
    private func header(_ page: SettingsPage) -> some View {
        Section {
            VStack(spacing: 8) {
                SettingsIcon(page: page, size: 48)
                Text(page.title).font(.title2.weight(.semibold))
                page.summary
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func content(_ page: SettingsPage) -> some View {
        switch page {
        case .general: general
        case .menuBar: menuBar
        case .touchBar: touchBarPage
        case .panel: panel
        case .alerts: alerts
        case .bluetooth: bluetooth
        case .clocks: clocks
        }
    }

    @ViewBuilder
    private var general: some View {
        @Bindable var preferences = preferences
        Section {
            LabeledContent {
                Slider(value: $preferences.refreshInterval, in: 0.5...5, step: 0.5)
                    .labelsHidden()
                    .frame(width: 180)
            } label: {
                Text("Refresh interval")
                Text("Sampling every \(ValueFormatter.seconds(preferences.refreshInterval))s. Lower is snappier, higher is kinder to the battery.")
            }
        }

        Section {
            // Written through a binding rather than `onChange` so that only the
            // user's own taps register the login item: refreshing the switch
            // from the system below must not write back.
            Toggle(isOn: Binding(
                get: { launchesAtLogin },
                set: { wanted in
                    launchesAtLogin = LoginItem.setEnabled(wanted) ? wanted : LoginItem.isEnabled
                }
            )) {
                Text("Open at login")
                Text("Starts in the menu bar, with no Dock icon.")
            }
        }
        // The switch also lives in System Settings, so the window can be
        // sitting on a stale answer by the time it is looked at again.
        .onAppear { launchesAtLogin = LoginItem.isEnabled }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchesAtLogin = LoginItem.isEnabled
        }
    }

    @ViewBuilder
    private var menuBar: some View {
        @Bindable var preferences = preferences
        Section {
            Picker("Menu bar", selection: $preferences.menuBarStyle) {
                ForEach(Preferences.MenuBarStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            // Only what this Mac can actually report: offering "Fans" on a
            // fanless Mac just pins the status item to n/a.
            WithSnapshot(readings: live, monitor: monitor) { snapshot in
                Picker("Menu bar metric", selection: $preferences.menuBarMetric) {
                    ForEach(Self.reportableMetrics(in: snapshot)) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
            }
            .disabled(preferences.menuBarStyle == .graph)
        }

        Section {
            Toggle(isOn: $preferences.isMenuBarRealTime) {
                Text("Real-time menu bar")
                Text("Follows every sample, the same figure as the panel. Off, it is redrawn every few seconds with the average since the last one, which costs about half as much.")
            }
            .disabled(preferences.menuBarStyle == .icon)
        }
    }

    // MARK: Touch Bar

    @ViewBuilder
    private var touchBarPage: some View {
        @Bindable var preferences = preferences
        let isEnabled = preferences.isTouchBarEnabled

        if !touchBar.isSupported {
            Section {
                Label("No Touch Bar detected on this Mac. The setting is kept for when GlassDeck runs on one.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }

        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                ForEach(TouchBarStyle.allCases) { style in
                    styleTile(style)
                }
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Detail, when a panel is tapped")
                TouchBarDetailPreview(style: preferences.touchBarStyle)
                    .aspectRatio(TouchBarDetailPreview.aspectRatio, contentMode: .fit)
                    .touchBarPreviewFrame()
            }
        } header: {
            Text("Style")
        } footer: {
            Text("\(preferences.touchBarStyle.summary) Applies to the full and compact bar, and to a metric's detail.")
        }

        Section {
            Toggle("Show GlassDeck on the Touch Bar", isOn: $preferences.isTouchBarEnabled)
            Picker(selection: $preferences.touchBarPresentation) {
                ForEach(Preferences.TouchBarPresentation.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                Text("Placement")
                Text(preferences.touchBarPresentation.explanation)
            }
            .disabled(!isEnabled)
            Picker("Position", selection: $preferences.touchBarAlignment) {
                ForEach(Preferences.TouchBarAlignment.allCases) { alignment in
                    Text(alignment.title).tag(alignment)
                }
            }
            .disabled(!isEnabled)
            LabeledContent("Hand-over shortcut") {
                ShortcutRecorder(shortcut: $preferences.yieldShortcut) { touchBar.suspendShortcut($0) }
            }
            .disabled(!isEnabled)
        } header: {
            Text("Presentation")
        } footer: {
            Text("The shrink button steps down through full width, the compact bar and a small meter; only a tap on the smallest one hands the Touch Bar back, and the Control Strip meter brings it straight back.")
        }

        Section {
            ForEach(preferences.metricOrder) { kind in
                metricToggle(kind, in: \.touchBarMetrics)
            }
        } header: {
            Text("Metrics")
        } footer: {
            Text("Their order is the one set in Panel and dashboard.")
        }

        Section {
            Picker("Pet", selection: $preferences.touchBarPet) {
                ForEach(TouchBarPet.allCases) { pet in
                    Text(pet.title).tag(pet)
                }
            }
            .disabled(!isEnabled)
        } footer: {
            Text("Now and then it walks across the full and compact bar, and it always turns up when the Mac starts working hard or heating up. Its mood follows the readings; tap it to say hello.")
        }
    }

    /// One style as System Settings shows a choice of appearance: a picture
    /// of it, its name underneath, and a ring round the one in use.
    private func styleTile(_ style: TouchBarStyle) -> some View {
        let isSelected = preferences.touchBarStyle == style
        return Button { preferences.touchBarStyle = style } label: {
            VStack(spacing: 6) {
                TouchBarStylePreview(style: style)
                    .frame(height: 30)
                    .touchBarPreviewFrame(isSelected: isSelected)
                Text(style.title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(style.summary)
        .accessibilityLabel(style.title)
        .accessibilityHint(style.summary)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// A metric's switch, with what reading it costs where that is worth
    /// knowing before switching it on.
    private func metricToggle(_ kind: MetricKind, in keyPath: ReferenceWritableKeyPath<Preferences, [MetricKind]>) -> some View {
        Toggle(isOn: binding(for: kind, keyPath: keyPath)) {
            Label {
                Text(kind.title)
                if let interval = kind.smcCacheInterval {
                    Text("SMC, cached \(Int(interval)) s")
                }
            } icon: {
                Image(systemName: kind.symbolName)
                    .foregroundStyle(Theme.accent(kind))
                    .frame(width: 20)
            }
        }
    }

    // MARK: Monitor

    @ViewBuilder
    private var panel: some View {
        @Bindable var preferences = preferences
        Section {
            ForEach(preferences.metricOrder) { kind in
                metricToggle(kind, in: \.dashboardMetrics)
            }
            .onMove { self.preferences.moveMetrics(fromOffsets: $0, toOffset: $1) }
        } header: {
            Text("Metrics")
        } footer: {
            Text("Drag to reorder. The order is shared by the panel, the Touch Bar and the menu bar.")
        }

        Section {
            Toggle(isOn: $preferences.showsProcesses) {
                Text("Show top processes")
                Text("Sampled only while the panel is open.")
            }
        }
    }

    @ViewBuilder
    private var alerts: some View {
        @Bindable var preferences = preferences
        Section {
            WithSnapshot(readings: live, monitor: monitor) { snapshot in
                if snapshot.supports(.temperature) {
                    Toggle(isOn: alertBinding(\.isTemperatureAlertEnabled)) {
                        Text("Warn when the Mac runs hot")
                        Text("A notification once the hottest sensor passes \(Int(preferences.temperatureThreshold))°C, and not again until it has cooled down.")
                    }
                    if preferences.isTemperatureAlertEnabled {
                        LabeledContent("Warn above") {
                            HStack(spacing: 8) {
                                Slider(value: $preferences.temperatureThreshold, in: 60...100, step: 5)
                                    .labelsHidden()
                                    .frame(width: 150)
                                Text(verbatim: ValueFormatter.celsius(preferences.temperatureThreshold))
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            Toggle(isOn: alertBinding(\.isMemoryPressureAlertEnabled)) {
                Text("Warn when memory runs short")
                Text("A notification when macOS reports high memory pressure, and again if it turns critical. A full memory bar on its own is normal on a Mac.")
            }
        }
    }

    // MARK: Modules

    @ViewBuilder
    private var bluetooth: some View {
        Section {
            Toggle(isOn: moduleBinding(.bluetooth)) {
                Text(ModuleKind.bluetooth.title)
                Text("macOS asks for permission the first time this is switched on.")
            }
            // Only once the module is on: with it off nothing is sampled, so
            // "nothing is reporting" would be true of every Mac.
            if preferences.panelModules.contains(.bluetooth) {
                WithSnapshot(readings: live, monitor: monitor) { snapshot in
                    if !snapshot.bluetooth.isAvailable {
                        Label("Nothing paired is reporting a battery level right now.", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var clocks: some View {
        Section {
            Toggle(ModuleKind.clock.title, isOn: moduleBinding(.clock))
            Picker("Show in the menu bar", selection: menuBarZoneBinding) {
                Text("Off").tag(String?.none)
                ForEach(preferences.clockZones) { zone in
                    Text(zone.displayLabel).tag(String?.some(zone.identifier))
                }
            }
            .disabled(preferences.clockZones.isEmpty)
        }

        Section("Time zones") {
            ForEach(preferences.clockZones) { zone in
                zoneRow(zone)
            }
            .onMove { self.preferences.moveClockZones(fromOffsets: $0, toOffset: $1) }

            HStack {
                Spacer()
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
                .fixedSize()
            }
        }
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
            .labelsHidden()
            .frame(maxWidth: 160)

            Text(zone.identifier)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)

            Spacer(minLength: 4)

            if let timeZone = zone.timeZone {
                Text(WorldClock.time(in: timeZone, at: clock.now))
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

    // MARK: - Bindings and readings

    private var menuBarZoneBinding: Binding<String?> {
        Binding(
            get: { preferences.menuBarClockZone },
            set: { preferences.menuBarClockZone = $0 }
        )
    }

    /// An alert's switch. Permission to notify is asked for only when one is
    /// turned on, never before.
    private func alertBinding(_ keyPath: ReferenceWritableKeyPath<Preferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { preferences[keyPath: keyPath] },
            set: { enabled in
                preferences[keyPath: keyPath] = enabled
                if enabled { ThresholdAlerts.requestAuthorization() }
            }
        )
    }

    private func moduleBinding(_ module: ModuleKind) -> Binding<Bool> {
        Binding(
            get: { preferences.panelModules.contains(module) },
            set: { _ in preferences.toggle(module) }
        )
    }

    /// Metrics this machine reports. Before the first sample nothing
    /// hardware-dependent is known yet, so the full list stands in.
    private static func reportableMetrics(in snapshot: MetricsSnapshot) -> [MetricKind] {
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

/// Reads the live snapshot in a body of its own.
///
/// Only a few rows depend on the reading — which metrics this Mac can report,
/// the temperature switch, the Bluetooth notice — and `@Observable` charges
/// the read to whichever body makes it. Made here, a sample re-evaluates
/// those rows alone rather than the whole window with its sidebar.
private struct WithSnapshot<Content: View>: View {
    let readings: LiveReadings
    let monitor: SystemMonitor
    @ViewBuilder let content: (MetricsSnapshot) -> Content

    var body: some View { content(readings.snapshot(from: monitor)) }
}

/// Names the window after the page, which is the title System Settings shows
/// in its toolbar. A hosting controller does not pass a split view's
/// navigation title through to a window it did not open, so the title is set
/// on the controller, whose title the window follows.
private struct WindowTitle: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> TitleView { TitleView() }

    func updateNSView(_ view: TitleView, context: Context) {
        view.title = title
    }

    final class TitleView: NSView {
        var title = "" {
            didSet { if title != oldValue { apply() } }
        }

        // The first title arrives before the view is in a window.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            guard let controller = window?.contentViewController, controller.title != title else { return }
            controller.title = title
        }
    }
}

private extension View {
    /// The black of the bar behind a Touch Bar preview, ringed in the accent
    /// colour when it is the style in use.
    func touchBarPreviewFrame(isSelected: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.TouchBar.chipRadius, style: .continuous)
        return padding(4)
            .background(Color.black, in: shape)
            .overlay {
                shape.strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2.5 : 1)
            }
            .accessibilityHidden(true)
    }
}
