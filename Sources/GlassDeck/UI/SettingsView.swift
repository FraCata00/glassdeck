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

    enum Group: CaseIterable {
        case essentials, monitor, modules

        var title: Text {
            switch self {
            case .essentials: Text("Essentials")
            case .monitor: Text("Monitor")
            case .modules: Text("Modules")
            }
        }
    }

    var group: Group {
        switch self {
        case .general, .menuBar, .touchBar: .essentials
        case .panel, .alerts: .monitor
        case .bluetooth, .clocks: .modules
        }
    }

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
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .touchBar: "rectangle.and.hand.point.up.left"
        case .panel: "square.grid.2x2"
        case .alerts: "bell"
        case .bluetooth: ModuleKind.bluetooth.symbolName
        case .clocks: ModuleKind.clock.symbolName
        }
    }

    /// Words the search field also matches, beyond the page's title: the
    /// names of the settings on it.
    var keywords: [String] {
        switch self {
        case .general: [String(localized: "Refresh interval"), String(localized: "Open at login")]
        case .menuBar: [String(localized: "Menu bar metric")]
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

/// Settings window: a sidebar of pages, each a stack of cards.
struct SettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(TouchBarController.self) private var touchBar
    @Environment(SystemMonitor.self) private var monitor
    @Environment(ClockTicker.self) private var clock
    @Environment(\.controlActiveState) private var controlActiveState

    @State private var page: SettingsPage = .general
    @State private var query = ""
    @State private var touchBarPart: TouchBarPart = .style
    @State private var launchesAtLogin = LoginItem.isEnabled
    @State private var live = LiveReadings()

    enum TouchBarPart: Hashable { case style, placement, metrics }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    content
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(page)
        }
        .frame(width: SettingsMetrics.windowSize.width, height: SettingsMetrics.windowSize.height)
        // The window outlives its closing — `isReleasedWhenClosed` is false — so
        // the gate the panel and the dashboard need applies here too.
        .tracksVisibility($live, monitor: monitor, clock: clock)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search settings", text: $query)
                    .textFieldStyle(.plain)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Theme.Settings.pill, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
            .padding(.bottom, 4)

            ForEach(SettingsPage.Group.allCases, id: \.self) { group in
                let pages = SettingsPage.allCases.filter { $0.group == group && $0.matches(query) }
                if !pages.isEmpty {
                    group.title
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                        .padding(.bottom, 2)
                        .padding(.leading, 8)
                    ForEach(pages) { sidebarButton($0) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: SettingsMetrics.sidebarWidth)
    }

    private func sidebarButton(_ item: SettingsPage) -> some View {
        let isSelected = item == page
        // An inactive window drains the accent out of the glass, and white
        // text on the grey that is left is barely legible.
        let isHighlighted = isSelected && controlActiveState != .inactive
        return Button { page = item } label: {
            HStack(spacing: 8) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(isHighlighted ? Color.white : Color.accentColor)
                    .frame(width: 18)
                Text(item.title).font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .foregroundStyle(isHighlighted ? Color.white : Color.primary)
            .modifier(SidebarSelection(isSelected: isSelected))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Pages

    @ViewBuilder
    private var content: some View {
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

    private func pageTitle(_ page: SettingsPage) -> some View {
        Text(page.title).font(.system(size: 15, weight: .bold))
    }

    private var general: some View {
        @Bindable var preferences = preferences
        return Group {
            SettingsIntroCard(header: { pageTitle(.general) }, text: Text("How often GlassDeck samples and how it starts. Nothing here uses the network."))

            SettingsSectionHeader(Text("Sampling"))
            SettingsCard {
                SettingsRow(
                    symbol: "timer",
                    title: Text("Refresh interval"),
                    subtitle: Text("Sampling every \(ValueFormatter.seconds(preferences.refreshInterval))s. Lower is snappier, higher is kinder to the battery.")
                ) {
                    Slider(value: $preferences.refreshInterval, in: 0.5...5, step: 0.5)
                        .frame(width: 150)
                        .labelsHidden()
                }
            }

            SettingsSectionHeader(Text("Start-up"))
            SettingsCard {
                SettingsRow(symbol: "power", title: Text("Open at login"), subtitle: Text("Starts in the menu bar, with no Dock icon.")) {
                    // Written through a binding rather than `onChange` so that only
                    // the user's own taps register the login item: refreshing the
                    // toggle from the system below must not write back.
                    Toggle("Open at login", isOn: Binding(
                        get: { launchesAtLogin },
                        set: { wanted in
                            launchesAtLogin = LoginItem.setEnabled(wanted) ? wanted : LoginItem.isEnabled
                        }
                    ))
                    .settingsSwitch()
                }
            }
            // The switch also lives in System Settings, so the window can be
            // sitting on a stale answer by the time it is looked at again.
            .onAppear { launchesAtLogin = LoginItem.isEnabled }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                launchesAtLogin = LoginItem.isEnabled
            }
        }
    }

    private var menuBar: some View {
        @Bindable var preferences = preferences
        return Group {
            SettingsIntroCard(header: { pageTitle(.menuBar) }, text: Text("What the icon in the menu bar shows. It is redrawn only when the label would actually look different."))

            SettingsSectionHeader(Text("Label"))
            SettingsCard {
                SettingsRow(symbol: "menubar.rectangle", title: Text("Menu bar")) {
                    Picker("Menu bar", selection: $preferences.menuBarStyle) {
                        ForEach(Preferences.MenuBarStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRowDivider()
                // Only what this Mac can actually report: offering "Fans" on a
                // fanless Mac just pins the status item to n/a.
                SettingsRow(symbol: "chart.bar", title: Text("Menu bar metric")) {
                    WithSnapshot(readings: live, monitor: monitor) { snapshot in
                        Picker("Menu bar metric", selection: $preferences.menuBarMetric) {
                            ForEach(Self.reportableMetrics(in: snapshot)) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(preferences.menuBarStyle == .graph)
                }
            }
        }
    }

    // MARK: Touch Bar

    private var touchBarPage: some View {
        Group {
            switch touchBarPart {
            case .style: touchBarStyle
            case .placement: touchBarPlacement
            case .metrics: touchBarMetrics
            }
        }
    }

    private var touchBarSegments: some View {
        SettingsSegments(
            options: [
                (TouchBarPart.style, Text("Style")),
                (TouchBarPart.placement, Text("Placement")),
                (TouchBarPart.metrics, Text("Metrics")),
            ],
            selection: $touchBarPart
        )
    }

    private var touchBarStyle: some View {
        Group {
            SettingsIntroCard(
                header: { touchBarSegments },
                text: Text("Choose how the metric panels are drawn on the Touch Bar. Only the painting changes: sampling stays exactly the same.")
            ) {
                Text("Style in use: \(preferences.touchBarStyle.title)").foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { preferences.touchBarStyle = .glass }
                    .glassButton()
                    .disabled(preferences.touchBarStyle == .glass)
            }

            SettingsSectionHeader(Text("Strip style"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(TouchBarStyle.allCases) { style in
                    styleCard(style)
                }
            }
            .padding(10)
            .settingsCardBackground()
            SettingsFootnote(Text("Applies to the full-width and compact bar. The Control Strip meter and a metric's detail keep their own look."))
            if !touchBar.isSupported { noTouchBarNotice }
        }
    }

    private func styleCard(_ style: TouchBarStyle) -> some View {
        let isInUse = preferences.touchBarStyle == style
        return VStack(alignment: .leading, spacing: 6) {
            TouchBarStylePreview(style: style)
                .frame(height: 30)
                .padding(4)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            Text(style.title).font(Typography.title)
            Text(style.summary)
                .font(Typography.body)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            Button(isInUse ? "In use" : "Apply") { preferences.touchBarStyle = style }
                .glassButton(prominent: isInUse)
                .allowsHitTesting(!isInUse)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Settings.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isInUse ? 2 : 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isInUse ? [.isSelected] : [])
    }

    private var touchBarPlacement: some View {
        @Bindable var preferences = preferences
        let isEnabled = preferences.isTouchBarEnabled
        return Group {
            SettingsIntroCard(
                header: { touchBarSegments },
                text: Text("Where GlassDeck sits on the Touch Bar, and how it hands the bar to other apps.")
            )

            SettingsSectionHeader(Text("Presentation"))
            SettingsCard {
                SettingsRow(symbol: "rectangle.and.hand.point.up.left", title: Text("Show GlassDeck on the Touch Bar")) {
                    Toggle("Show GlassDeck on the Touch Bar", isOn: $preferences.isTouchBarEnabled).settingsSwitch()
                }
                SettingsRowDivider()
                SettingsRow(
                    symbol: "rectangle.split.3x1",
                    title: Text("Placement"),
                    subtitle: Text(preferences.touchBarPresentation.explanation)
                ) {
                    Picker("Placement", selection: $preferences.touchBarPresentation) {
                        ForEach(Preferences.TouchBarPresentation.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!isEnabled)
                }
                SettingsRowDivider()
                SettingsRow(symbol: "align.horizontal.right", title: Text("Position")) {
                    Picker("Position", selection: $preferences.touchBarAlignment) {
                        ForEach(Preferences.TouchBarAlignment.allCases) { alignment in
                            Text(alignment.title).tag(alignment)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!isEnabled)
                }
                SettingsRowDivider()
                SettingsRow(symbol: "command", title: Text("Hand-over shortcut")) {
                    ShortcutRecorder(shortcut: $preferences.yieldShortcut) { touchBar.suspendShortcut($0) }
                        .disabled(!isEnabled)
                }
            }
            SettingsFootnote(Text("The shrink button steps down through full width, the compact bar and a small meter; only a tap on the smallest one hands the Touch Bar back, and the Control Strip meter brings it straight back."))
            if !touchBar.isSupported { noTouchBarNotice }
        }
    }

    private var touchBarMetrics: some View {
        let selected = selectedCount(\.touchBarMetrics)
        return Group {
            SettingsIntroCard(
                header: { touchBarSegments },
                text: Text("Which metrics appear on the Touch Bar. Their order is the one set in Panel and dashboard.")
            ) {
                Text("\(selected) of \(preferences.metricOrder.count) metrics on the Touch Bar").foregroundStyle(.secondary)
            }

            SettingsSectionHeader(Text("Metrics in the Touch Bar strip"))
            SettingsCard {
                ForEach(Array(preferences.metricOrder.enumerated()), id: \.element) { index, kind in
                    if index > 0 { SettingsRowDivider() }
                    SettingsRow(symbol: kind.symbolName, title: Text(kind.title), tag: costTag(for: kind)) {
                        Toggle(kind.title, isOn: binding(for: kind, keyPath: \.touchBarMetrics)).settingsSwitch()
                    }
                }
            }
        }
    }

    private var noTouchBarNotice: some View {
        Label("No Touch Bar detected on this Mac. The setting is kept for when GlassDeck runs on one.", systemImage: "info.circle")
            .font(Typography.body)
            .foregroundStyle(.secondary)
    }

    /// The readings that cost a kernel round trip per key, and how long each is
    /// kept. Worth saying beside the switch, since turning one on is what makes
    /// the SMC get asked at all.
    private func costTag(for kind: MetricKind) -> Text? {
        kind.smcCacheInterval.map { Text("SMC, cached \(Int($0)) s") }
    }

    // MARK: Monitor

    /// A `List` inside the card, because rows have to be draggable and only a
    /// list carries `onMove` on macOS. It does not scroll on its own: the page
    /// does, and it is given the height of its rows.
    private var panel: some View {
        @Bindable var preferences = preferences
        let selected = selectedCount(\.dashboardMetrics)
        return Group {
            SettingsIntroCard(
                header: { pageTitle(.panel) },
                text: Text("The metrics in the panel and the dashboard. The order set here is shared by every surface.")
            ) {
                Text("\(selected) of \(preferences.metricOrder.count) metrics shown").foregroundStyle(.secondary)
            }

            SettingsSectionHeader(Text("Shown in the panel and dashboard"))
            List {
                ForEach(preferences.metricOrder) { kind in
                    SettingsRow(symbol: kind.symbolName, title: Text(kind.title), tag: costTag(for: kind)) {
                        Toggle(kind.title, isOn: binding(for: kind, keyPath: \.dashboardMetrics)).settingsSwitch()
                    }
                    .listRowSeparator(.visible)
                    .listRowBackground(Color.clear)
                }
                .onMove { self.preferences.moveMetrics(fromOffsets: $0, toOffset: $1) }
            }
            .settingsEmbeddedList(rows: preferences.metricOrder.count, rowHeight: SettingsMetrics.metricRowHeight)
            SettingsFootnote(Text("Drag to reorder. The order is shared by the panel, the Touch Bar and the menu bar."))

            SettingsSectionHeader(Text("Processes"))
            SettingsCard {
                SettingsRow(
                    symbol: "list.bullet.rectangle",
                    title: Text("Show top processes"),
                    subtitle: Text("Sampled only while the panel is open."),
                    tag: Text("Only while visible")
                ) {
                    Toggle("Show top processes", isOn: $preferences.showsProcesses).settingsSwitch()
                }
            }
        }
    }

    private var alerts: some View {
        @Bindable var preferences = preferences
        return Group {
            SettingsIntroCard(
                header: { pageTitle(.alerts) },
                text: Text("Notifications when something needs attention. They read the slow reading, at most every two seconds.")
            )

            SettingsSectionHeader(Text("When to warn"))
            SettingsCard {
                WithSnapshot(readings: live, monitor: monitor) { snapshot in
                    if snapshot.supports(.temperature) {
                        SettingsRow(
                            symbol: "thermometer.medium",
                            title: Text("Warn when the Mac runs hot"),
                            subtitle: Text("A notification once the hottest sensor passes \(Int(preferences.temperatureThreshold))°C, and not again until it has cooled down."),
                            tag: costTag(for: .temperature)
                        ) {
                            Toggle("Warn when the Mac runs hot", isOn: alertBinding(\.isTemperatureAlertEnabled))
                                .settingsSwitch()
                        }
                        if preferences.isTemperatureAlertEnabled {
                            SettingsRowDivider()
                            SettingsRow(symbol: "dial.medium", title: Text("Warn above")) {
                                HStack(spacing: 8) {
                                    Slider(value: $preferences.temperatureThreshold, in: 60...100, step: 5)
                                        .frame(width: 130)
                                        .labelsHidden()
                                    Text(verbatim: ValueFormatter.celsius(preferences.temperatureThreshold))
                                        .font(.system(size: 12))
                                        .monospacedDigit()
                                        .frame(width: 40, alignment: .trailing)
                                }
                            }
                        }
                        SettingsRowDivider()
                    }
                }
                SettingsRow(
                    symbol: "memorychip",
                    title: Text("Warn when memory runs short"),
                    subtitle: Text("A notification when macOS reports high memory pressure, and again if it turns critical. A full memory bar on its own is normal on a Mac.")
                ) {
                    Toggle("Warn when memory runs short", isOn: alertBinding(\.isMemoryPressureAlertEnabled))
                        .settingsSwitch()
                }
            }
        }
    }

    // MARK: Modules

    private var bluetooth: some View {
        Group {
            SettingsIntroCard(
                header: { pageTitle(.bluetooth) },
                text: Text("The charge of every paired device that reports one. A device that is not connected keeps publishing the level it was last seen at, so those rows are dimmed and marked rather than hidden.")
            )

            SettingsSectionHeader(Text("Devices"))
            SettingsCard {
                SettingsRow(
                    symbol: ModuleKind.bluetooth.symbolName,
                    title: Text(ModuleKind.bluetooth.title),
                    subtitle: Text("macOS asks for permission the first time this is switched on."),
                    tag: Text("Asks for permission")
                ) {
                    Toggle(ModuleKind.bluetooth.title, isOn: moduleBinding(.bluetooth)).settingsSwitch()
                }
            }
            // Only once the module is on: with it off nothing is sampled, so
            // "nothing is reporting" would be true of every Mac.
            if preferences.panelModules.contains(.bluetooth) {
                WithSnapshot(readings: live, monitor: monitor) { snapshot in
                    if !snapshot.bluetooth.isAvailable {
                        Label("Nothing paired is reporting a battery level right now.", systemImage: "info.circle")
                            .font(Typography.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var clocks: some View {
        Group {
            SettingsIntroCard(
                header: { pageTitle(.clocks) },
                text: Text("Rename a row to whatever the clock is for. Drag to reorder.")
            ) {
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
                .menuStyle(.button)
                .glassButton()
                .fixedSize()
            }

            SettingsSectionHeader(Text("Time zones"))
            SettingsCard {
                SettingsRow(symbol: ModuleKind.clock.symbolName, title: Text(ModuleKind.clock.title)) {
                    Toggle(ModuleKind.clock.title, isOn: moduleBinding(.clock)).settingsSwitch()
                }
                SettingsRowDivider()
                SettingsRow(symbol: "menubar.rectangle", title: Text("Show in the menu bar")) {
                    Picker("Show in the menu bar", selection: menuBarZoneBinding) {
                        Text("Off").tag(String?.none)
                        ForEach(preferences.clockZones) { zone in
                            Text(zone.displayLabel).tag(String?.some(zone.identifier))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(preferences.clockZones.isEmpty)
                }
            }

            if !preferences.clockZones.isEmpty {
                List {
                    ForEach(preferences.clockZones) { zone in
                        zoneRow(zone)
                            .padding(.vertical, 4)
                            .listRowBackground(Color.clear)
                    }
                    .onMove { self.preferences.moveClockZones(fromOffsets: $0, toOffset: $1) }
                }
                .settingsEmbeddedList(rows: preferences.clockZones.count, rowHeight: SettingsMetrics.zoneRowHeight)
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
                    .font(Typography.label)
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

    /// How many metrics a selection holds, counted against the full order.
    private func selectedCount(_ keyPath: KeyPath<Preferences, [MetricKind]>) -> Int {
        preferences.metricOrder.filter(preferences[keyPath: keyPath].contains).count
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

/// The selected sidebar row: accent-tinted glass, so the selection reads as
/// the material taking on colour — the app's selection language — rather than
/// as a flat fill.
private struct SidebarSelection: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content.glassSurface(cornerRadius: 7, tint: .accentColor)
        } else {
            content
        }
    }
}
