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
        static let showsProcesses = "showsProcesses"
    }

    /// How the status item renders in the menu bar.
    enum MenuBarStyle: String, CaseIterable, Identifiable {
        case graph
        case percentage
        case icon

        var id: String { rawValue }
        var title: String {
            switch self {
            case .graph: "Live bars"
            case .percentage: "Icon + value"
            case .icon: "Icon only"
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
            case .controlStrip: "Control Strip button"
            case .alwaysOn: "Take over the whole Touch Bar"
            }
        }

        var explanation: String {
            switch self {
            case .controlStrip:
                "A compact meter sits in the expanded Control Strip. Tap it for the full-width graphs."
            case .alwaysOn:
                "GlassDeck occupies the entire Touch Bar. Other apps' bars still take priority while they are frontmost."
            }
        }
    }

    private let defaults: UserDefaults

    var refreshInterval: Double { didSet { defaults.set(refreshInterval, forKey: Key.interval) } }
    var dashboardMetrics: [MetricKind] { didSet { store(dashboardMetrics, forKey: Key.dashboardMetrics) } }
    var touchBarMetrics: [MetricKind] { didSet { store(touchBarMetrics, forKey: Key.touchBarMetrics) } }
    var menuBarMetric: MetricKind { didSet { defaults.set(menuBarMetric.rawValue, forKey: Key.menuBarMetric) } }
    var menuBarStyle: MenuBarStyle { didSet { defaults.set(menuBarStyle.rawValue, forKey: Key.menuBarStyle) } }
    var isTouchBarEnabled: Bool { didSet { defaults.set(isTouchBarEnabled, forKey: Key.touchBarEnabled) } }
    var touchBarPresentation: TouchBarPresentation {
        didSet { defaults.set(touchBarPresentation.rawValue, forKey: Key.touchBarPresentation) }
    }
    var showsProcesses: Bool { didSet { defaults.set(showsProcesses, forKey: Key.showsProcesses) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedInterval = defaults.double(forKey: Key.interval)
        refreshInterval = storedInterval > 0 ? storedInterval : 1.5
        dashboardMetrics = Self.read(Key.dashboardMetrics, from: defaults) ?? MetricKind.allCases
        touchBarMetrics = Self.read(Key.touchBarMetrics, from: defaults) ?? MetricKind.defaultSelection
        menuBarMetric = defaults.string(forKey: Key.menuBarMetric).flatMap(MetricKind.init(rawValue:)) ?? .cpu
        menuBarStyle = defaults.string(forKey: Key.menuBarStyle).flatMap(MenuBarStyle.init(rawValue:)) ?? .graph
        isTouchBarEnabled = defaults.object(forKey: Key.touchBarEnabled) as? Bool ?? true
        touchBarPresentation = defaults.string(forKey: Key.touchBarPresentation)
            .flatMap(TouchBarPresentation.init(rawValue:)) ?? .controlStrip
        showsProcesses = defaults.object(forKey: Key.showsProcesses) as? Bool ?? true
    }

    /// Toggles a metric in a selection while keeping the canonical metric order
    /// and refusing to empty the list — an empty Touch Bar strip would look broken.
    func toggle(_ kind: MetricKind, in keyPath: ReferenceWritableKeyPath<Preferences, [MetricKind]>) {
        var selection = self[keyPath: keyPath]
        if let index = selection.firstIndex(of: kind) {
            guard selection.count > 1 else { return }
            selection.remove(at: index)
        } else {
            selection.append(kind)
            selection = MetricKind.allCases.filter(selection.contains)
        }
        self[keyPath: keyPath] = selection
    }

    private func store(_ metrics: [MetricKind], forKey key: String) {
        defaults.set(metrics.map(\.rawValue), forKey: key)
    }

    private static func read(_ key: String, from defaults: UserDefaults) -> [MetricKind]? {
        guard let raw = defaults.array(forKey: key) as? [String] else { return nil }
        let metrics = raw.compactMap(MetricKind.init(rawValue:))
        return metrics.isEmpty ? nil : metrics
    }
}
