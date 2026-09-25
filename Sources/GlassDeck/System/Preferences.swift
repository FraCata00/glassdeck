import Foundation
import GlassDeckKit
import Observation

/// User-visible settings, persisted in `UserDefaults` and observable by SwiftUI.
@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let interval = "refreshInterval"
        static let dashboardMetrics = "dashboardMetrics"
        static let touchBarMetrics = "touchBarMetrics"
        static let menuBarMetric = "menuBarMetric"
        static let menuBarStyle = "menuBarStyle"
        static let touchBarEnabled = "touchBarEnabled"
        static let touchBarPresentation = "touchBarPresentation"
        static let touchBarAlignment = "touchBarAlignment"
        static let showsProcesses = "showsProcesses"
        static let metricOrder = "metricOrder"
        static let temperatureAlert = "temperatureAlert"
        static let temperatureThreshold = "temperatureThreshold"
        static let panelModules = "panelModules"
        static let clockZones = "clockZones"
        static let menuBarClockZone = "menuBarClockZone"
    }

    /// How the status item renders in the menu bar.
    enum MenuBarStyle: String, CaseIterable, Identifiable {
        case graph
        case percentage
        case icon

        var id: String { rawValue }
        var title: String {
            switch self {
            case .graph: String(localized: "Live bars")
            case .percentage: String(localized: "Icon + value")
            case .icon: String(localized: "Icon only")
            }
        }
    }

    /// Where GlassDeck lives on the Touch Bar.
    enum TouchBarPresentation: String, CaseIterable, Identifiable {
        /// A compact meter in the Control Strip; tap it to expand the full bar.
        case controlStrip
        /// The full Touch Bar is taken over by GlassDeck until the user turns it off.
        case alwaysOn

        var id: String { rawValue }
        var title: String {
            switch self {
            case .controlStrip: String(localized: "Control Strip button")
            case .alwaysOn: String(localized: "Take over the whole Touch Bar")
            }
        }

        var explanation: String {
            switch self {
            case .controlStrip:
                String(localized: "A compact meter sits in the expanded Control Strip. Tap it for the full-width graphs.")
            case .alwaysOn:
                String(localized: "GlassDeck occupies the entire Touch Bar. Other apps' bars still take priority while they are frontmost.")
            }
        }
    }

    /// Where the meters sit on the bar when they are not using its full width.
    /// Defined in the kit, beside the layout that honours it.
    typealias TouchBarAlignment = GlassDeckKit.TouchBarAlignment

    private let defaults: UserDefaults

    var refreshInterval: Double { didSet { defaults.set(refreshInterval, forKey: Key.interval) } }
    var dashboardMetrics: [MetricKind] { didSet { defaults.store(dashboardMetrics, forKey: Key.dashboardMetrics) } }
    var touchBarMetrics: [MetricKind] { didSet { defaults.store(touchBarMetrics, forKey: Key.touchBarMetrics) } }
    var menuBarMetric: MetricKind { didSet { defaults.store(menuBarMetric, forKey: Key.menuBarMetric) } }
    var menuBarStyle: MenuBarStyle { didSet { defaults.store(menuBarStyle, forKey: Key.menuBarStyle) } }
    var isTouchBarEnabled: Bool { didSet { defaults.set(isTouchBarEnabled, forKey: Key.touchBarEnabled) } }
    var touchBarPresentation: TouchBarPresentation {
        didSet { defaults.store(touchBarPresentation, forKey: Key.touchBarPresentation) }
    }
    var touchBarAlignment: TouchBarAlignment { didSet { defaults.store(touchBarAlignment, forKey: Key.touchBarAlignment) } }
    var showsProcesses: Bool { didSet { defaults.set(showsProcesses, forKey: Key.showsProcesses) } }

    /// The non-scalar cards shown under the gauges, in the panel and the
    /// dashboard. Unlike the metric selections this one may be empty: both
    /// modules are extras, and neither has anything to say by default.
    var panelModules: [ModuleKind] { didSet { defaults.store(panelModules, forKey: Key.panelModules) } }

    /// The time zones on the clock card, in the order they are shown.
    var clockZones: [ClockZone] { didSet { storeClockZones() } }

    /// The zone whose time sits in the menu bar, or `nil` for none.
    ///
    /// Off by default: macOS already has a clock up there, and a second one is
    /// only worth its space to someone who asked for it.
    var menuBarClockZone: String? {
        didSet { defaults.set(menuBarClockZone, forKey: Key.menuBarClockZone) }
    }

    /// The order every surface lists metrics in — the panel's gauges, the Touch
    /// Bar's panels and the status item's bars. Holds all of them, selected or
    /// not, so turning one off and on again does not lose its place.
    var metricOrder: [MetricKind] { didSet { defaults.store(metricOrder, forKey: Key.metricOrder) } }

    /// Off by default: an app that asks to send notifications before it has been
    /// asked to do anything is a bad guest.
    var isTemperatureAlertEnabled: Bool {
        didSet { defaults.set(isTemperatureAlertEnabled, forKey: Key.temperatureAlert) }
    }

    /// Degrees Celsius. 85 is where a Mac is working hard but not yet throttling.
    var temperatureThreshold: Double {
        didSet { defaults.set(temperatureThreshold, forKey: Key.temperatureThreshold) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refreshInterval = defaults.positive(Key.interval) ?? SystemMonitor.defaultInterval
        // An empty metric list reads as none stored: an empty Touch Bar strip
        // would look broken, and nothing can be turned off below one anyway.
        dashboardMetrics = defaults.nonEmpty(Key.dashboardMetrics) ?? MetricKind.allCases
        touchBarMetrics = defaults.nonEmpty(Key.touchBarMetrics) ?? MetricKind.defaultSelection
        menuBarMetric = defaults.value(Key.menuBarMetric) ?? .cpu
        menuBarStyle = defaults.value(Key.menuBarStyle) ?? .graph
        isTouchBarEnabled = defaults.object(forKey: Key.touchBarEnabled) as? Bool ?? true
        touchBarPresentation = defaults.value(Key.touchBarPresentation) ?? .controlStrip
        touchBarAlignment = defaults.value(Key.touchBarAlignment) ?? .trailing
        showsProcesses = defaults.object(forKey: Key.showsProcesses) as? Bool ?? true
        panelModules = defaults.values(Key.panelModules) ?? ModuleKind.defaultSelection
        clockZones = Self.readClockZones(from: defaults)
        menuBarClockZone = defaults.string(forKey: Key.menuBarClockZone)
        metricOrder = Self.repairedOrder(defaults.nonEmpty(Key.metricOrder))
        isTemperatureAlertEnabled = defaults.object(forKey: Key.temperatureAlert) as? Bool ?? false
        temperatureThreshold = defaults.positive(Key.temperatureThreshold) ?? 85

        // Selections stored before the order was changed — or before this
        // version — are brought into line. Assigned here rather than through the
        // setters, so a launch that changes nothing writes nothing.
        dashboardMetrics = metricOrder.filter(dashboardMetrics.contains)
        touchBarMetrics = metricOrder.filter(touchBarMetrics.contains)
    }

    /// Moves metrics in the shared order and brings the selections along, so all
    /// three surfaces keep agreeing about what comes first.
    func moveMetrics(fromOffsets source: IndexSet, toOffset destination: Int) {
        var order = metricOrder
        order.move(fromOffsets: source, toOffset: destination)
        metricOrder = order
        dashboardMetrics = order.filter(dashboardMetrics.contains)
        touchBarMetrics = order.filter(touchBarMetrics.contains)
    }

    /// Keeps whatever order was stored, drops anything that is no longer a
    /// metric, and appends any kind added since — so a new metric shows up at
    /// the end instead of the list silently resetting.
    private static func repairedOrder(_ stored: [MetricKind]?) -> [MetricKind] {
        var order: [MetricKind] = []
        for kind in stored ?? [] where !order.contains(kind) { order.append(kind) }
        for kind in MetricKind.allCases where !order.contains(kind) { order.append(kind) }
        return order
    }

    /// Turns a module's card on or off. Unlike the metric selections this one is
    /// allowed to empty: no modules simply means no extra cards.
    func toggle(_ module: ModuleKind) {
        if let index = panelModules.firstIndex(of: module) {
            panelModules.remove(at: index)
        } else {
            panelModules = ModuleKind.allCases.filter { panelModules.contains($0) || $0 == module }
        }
    }

    /// Adds a zone to the clock card, ignoring one that is already there.
    func addClockZone(_ identifier: String) {
        guard TimeZone(identifier: identifier) != nil,
              !clockZones.contains(where: { $0.identifier == identifier })
        else { return }
        clockZones.append(ClockZone(identifier: identifier))
    }

    func removeClockZones(atOffsets offsets: IndexSet) {
        var zones = clockZones
        zones.remove(atOffsets: offsets)
        clockZones = zones
        // A zone that is no longer on the card cannot go on being the one in the
        // menu bar.
        if let menuBarClockZone, !zones.contains(where: { $0.identifier == menuBarClockZone }) {
            self.menuBarClockZone = nil
        }
    }

    func moveClockZones(fromOffsets source: IndexSet, toOffset destination: Int) {
        var zones = clockZones
        zones.move(fromOffsets: source, toOffset: destination)
        clockZones = zones
    }

    /// Renames one zone's row. An empty name is kept as such — `ClockZone`
    /// falls back to the city when it draws, which is what lets the field be
    /// cleared and retyped.
    func renameClockZone(_ identifier: String, to label: String) {
        guard let index = clockZones.firstIndex(where: { $0.identifier == identifier }) else { return }
        clockZones[index].label = label.trimmingCharacters(in: .whitespaces)
    }

    private func storeClockZones() {
        guard let data = try? JSONEncoder().encode(clockZones) else { return }
        defaults.set(data, forKey: Key.clockZones)
    }

    private static func readClockZones(from defaults: UserDefaults) -> [ClockZone] {
        guard let data = defaults.data(forKey: Key.clockZones),
              let zones = try? JSONDecoder().decode([ClockZone].self, from: data)
        else { return [] }
        // A zone macOS has dropped between releases would otherwise be a row
        // that can never show a time.
        return zones.filter { TimeZone(identifier: $0.identifier) != nil }
    }

    /// Toggles a metric in a selection while keeping the user's metric order and
    /// refusing to empty the list — an empty Touch Bar strip would look broken.
    func toggle(_ kind: MetricKind, in keyPath: ReferenceWritableKeyPath<Preferences, [MetricKind]>) {
        var selection = self[keyPath: keyPath]
        if let index = selection.firstIndex(of: kind) {
            guard selection.count > 1 else { return }
            selection.remove(at: index)
        } else {
            selection.append(kind)
            selection = metricOrder.filter(selection.contains)
        }
        self[keyPath: keyPath] = selection
    }
}

/// Settings are stored by raw value. Named apart from `set(_:forKey:)` on
/// purpose: that one takes `Any?`, and handed an enum it would store something
/// that is not a property list and bring the app down.
private extension UserDefaults {
    func store<Value: RawRepresentable<String>>(_ value: Value, forKey key: String) {
        set(value.rawValue, forKey: key)
    }

    func store<Value: RawRepresentable<String>>(_ values: [Value], forKey key: String) {
        set(values.map(\.rawValue), forKey: key)
    }

    /// The stored case, or `nil` when there is none or it is no longer a case.
    func value<Value: RawRepresentable<String>>(_ key: String) -> Value? {
        string(forKey: key).flatMap(Value.init(rawValue:))
    }

    /// The stored list, skipping anything that is no longer a case. `nil` only
    /// when nothing is stored, so a list emptied on purpose stays empty.
    func values<Value: RawRepresentable<String>>(_ key: String) -> [Value]? {
        (array(forKey: key) as? [String]).map { $0.compactMap(Value.init(rawValue:)) }
    }

    /// As `values(_:)`, but a list with nothing left in it reads as none stored.
    func nonEmpty<Value: RawRepresentable<String>>(_ key: String) -> [Value]? {
        values(key).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A stored number, or `nil` for none — `double(forKey:)` reads a missing
    /// key as `0`, which no setting that uses this can mean.
    func positive(_ key: String) -> Double? {
        let value = double(forKey: key)
        return value > 0 ? value : nil
    }
}

extension TouchBarAlignment {
    var title: String {
        switch self {
        case .leading: String(localized: "Left")
        case .center: String(localized: "Centre")
        case .trailing: String(localized: "Right, beside the Control Strip")
        }
    }
}
