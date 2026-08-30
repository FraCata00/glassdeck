import AppKit
import GlassDeckKit
import IOKit
import Observation
import SwiftUI

/// Owns GlassDeck's presence on the Touch Bar.
///
/// Three states, in increasing order of ambition:
/// - **collapsed** — a compact meter in the Control Strip,
/// - **expanded** — a bar of live graphs that leaves the system Control Strip visible,
/// - **fullscreen** — the whole Touch Bar, which is also where fan speeds appear
///   because that is the only state with room for them.
@MainActor
@Observable
final class TouchBarController: NSObject, NSTouchBarDelegate {
    enum Mode: Equatable {
        case collapsed
        case expanded
        case fullscreen

        /// Placement passed to the system: `0` keeps the Control Strip, `1` covers it.
        var placement: Int { self == .fullscreen ? 1 : 0 }
    }

    static let controlStripIdentifier = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.controlstrip")
    private static let barIdentifier = NSTouchBar.CustomizationIdentifier("dev.fracata00.glassdeck.bar")
    private static let collapseItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.collapse")
    private static let resizeItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.resize")
    private static let dashboardItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.dashboard")
    private static let batteryItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.battery")
    private static let metricItemPrefix = "dev.fracata00.glassdeck.metric."

    /// True when this Mac actually has a Touch Bar and the private hooks resolved.
    let isSupported: Bool

    private(set) var mode: Mode = .collapsed

    private let monitor: SystemMonitor
    private let preferences: Preferences
    private let stripView = TouchBarStripView()
    private let tapView = TouchBarTapView()
    private var stripItem: NSCustomTouchBarItem?
    private var presentedBar: NSTouchBar?
    private var metricViews: [MetricKind: TouchBarMetricView] = [:]
    private let batteryView = TouchBarBatteryView()
    private var activationObserver: NSObjectProtocol?
    private var presentedSignature: String?
    private var isObserving = false

    /// Called when the user asks for the full dashboard from the Touch Bar.
    var onOpenDashboard: (() -> Void)?

    init(monitor: SystemMonitor, preferences: Preferences) {
        self.monitor = monitor
        self.preferences = preferences
        self.isSupported = TouchBarHardware.isPresent && DFRSupport.isAvailable
        super.init()

        stripView.metrics = preferences.touchBarMetrics
        stripView.frame = tapView.bounds
        stripView.autoresizingMask = [.width, .height]
        tapView.addSubview(stripView)
        tapView.onTap = { [weak self] in self?.handleStripTap() }
    }

    // MARK: - Lifecycle

    /// Installs or removes the Control Strip item and applies the presentation
    /// mode. Safe to call whenever settings change.
    func synchroniseWithPreferences() {
        guard isSupported else { return }

        guard preferences.isTouchBarEnabled else {
            uninstall()
            return
        }

        install()
        stripView.metrics = preferences.touchBarMetrics
        rebuildBarIfNeeded()

        switch preferences.touchBarPresentation {
        case .controlStrip:
            if mode != .collapsed { collapse() }
            stopReasserting()
        case .alwaysOn:
            if mode == .collapsed { present(.expanded) }
            startReasserting()
        }
    }

    private func install() {
        guard stripItem == nil else { return }
        DFRSupport.setSystemModalShowsCloseBox(true)

        let item = NSCustomTouchBarItem(identifier: Self.controlStripIdentifier)
        item.view = tapView
        stripItem = item

        SystemTouchBar.addSystemTrayItem(item)
        DFRSupport.setControlStripPresence(Self.controlStripIdentifier, visible: true)
        startObserving()
    }

    private func uninstall() {
        stopReasserting()
        if let presentedBar {
            SystemTouchBar.dismissSystemModal(presentedBar)
            self.presentedBar = nil
            presentedSignature = nil
            mode = .collapsed
        }
        guard let stripItem else { return }
        DFRSupport.setControlStripPresence(Self.controlStripIdentifier, visible: false)
        SystemTouchBar.removeSystemTrayItem(stripItem)
        self.stripItem = nil
    }

    // MARK: - Modes

    /// Tapping the Control Strip meter opens the bar; tapping it again while the
    /// bar is up collapses it.
    private func handleStripTap() {
        mode == .collapsed ? present(.expanded) : collapse()
    }

    func present(_ newMode: Mode) {
        guard isSupported, newMode != .collapsed else { return collapse() }

        // Presented bars stack: leaving the previous one up means collapsing the
        // new one just reveals a stale bar underneath instead of returning the
        // Touch Bar to the system. Always take the old one down first.
        if let presentedBar {
            SystemTouchBar.dismissSystemModal(presentedBar)
            self.presentedBar = nil
        }

        // Switching between expanded and fullscreen changes both the item list
        // and the placement, so the bar is rebuilt rather than re-presented as is.
        let bar = makeBar(for: newMode)
        presentedBar = bar
        presentedSignature = layoutSignature(for: newMode)
        mode = newMode
        SystemTouchBar.presentSystemModal(bar, identifier: Self.controlStripIdentifier, placement: newMode.placement)
        refresh()
    }

    /// Returns the Touch Bar to the system, leaving the Control Strip meter behind.
    func collapse() {
        guard let presentedBar, mode != .collapsed else { return }
        SystemTouchBar.dismissSystemModal(presentedBar)
        self.presentedBar = nil
        presentedSignature = nil
        mode = .collapsed
    }

    /// The bar's own close button: collapse and stop re-presenting, so the choice sticks.
    @objc private func collapseFromTouchBar() {
        collapse()
        preferences.touchBarPresentation = .controlStrip
    }

    @objc private func toggleFullscreen() {
        present(mode == .fullscreen ? .expanded : .fullscreen)
    }

    @objc private func openDashboard() {
        onOpenDashboard?()
    }

    /// In take-over mode the bar has to be re-presented whenever another app puts
    /// its own Touch Bar up, which happens on every app switch.
    private func startReasserting() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.preferences.isTouchBarEnabled,
                      self.preferences.touchBarPresentation == .alwaysOn
                else { return }
                self.present(self.mode == .collapsed ? .expanded : self.mode)
            }
        }
    }

    private func stopReasserting() {
        guard let activationObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        self.activationObserver = nil
    }

    // MARK: - Data

    /// Re-renders whichever Touch Bar surfaces are on screen.
    private func refresh() {
        let snapshot = monitor.snapshot
        stripView.snapshot = snapshot
        batteryView.battery = snapshot.battery
        for (kind, view) in metricViews {
            view.snapshot = snapshot
            view.history = monitor.history(for: kind)
        }
    }

    /// Bridges the Observation framework to AppKit: every published snapshot
    /// re-arms the tracking closure, which is how `@Observable` is watched
    /// outside SwiftUI.
    private func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = monitor.snapshot
            _ = preferences.touchBarMetrics
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stripView.metrics = self.preferences.touchBarMetrics
                self.rebuildBarIfNeeded()
                self.refresh()
                self.observe()
            }
        }
    }

    // MARK: - Bar construction

    /// Fan speeds are deliberately fullscreen-only: the shorter bar has no room
    /// for a fifth panel without squeezing the graphs into illegibility. Battery
    /// is never a panel — it rides along as the compact chip on the right.
    private func metrics(for mode: Mode) -> [MetricKind] {
        var metrics = preferences.touchBarMetrics.filter { $0 != .fans && $0 != .battery }
        if mode == .fullscreen {
            if monitor.snapshot.fans.isAvailable { metrics.append(.fans) }
            return metrics
        }
        // Sharing the bar with the Control Strip leaves roughly 640 pt: four
        // narrow panels plus the controls is the most that stays legible.
        return Array(metrics.prefix(4))
    }

    /// The bar is built before the first sample lands, so battery and fan
    /// availability are unknown at that point. Both are re-checked here and the
    /// bar is rebuilt once the answer changes — otherwise the battery chip would
    /// stay missing for the whole session.
    private func rebuildBarIfNeeded() {
        guard mode != .collapsed else { return }
        let signature = layoutSignature(for: mode)
        guard signature != presentedSignature else { return }
        present(mode)
    }

    private func layoutSignature(for mode: Mode) -> String {
        let metrics = metrics(for: mode).map(\.rawValue).joined(separator: ",")
        return "\(mode)|\(metrics)|battery:\(monitor.snapshot.battery.isAvailable)"
    }

    private func makeBar(for mode: Mode) -> NSTouchBar {
        metricViews.removeAll()

        let bar = NSTouchBar()
        bar.delegate = self
        bar.customizationIdentifier = Self.barIdentifier
        // The system draws its own close box on the left while GlassDeck is
        // frontmost, so GlassDeck's own controls all live on the right.
        // Width budget: the Touch Bar is ~1000 pt, of which the system Control
        // Strip claims about 400 whenever GlassDeck is not full width. Items are
        // dropped rather than squeezed — the Dashboard button only earns its place
        // in full width, where the menu bar panel is not the closer alternative.
        bar.defaultItemIdentifiers =
            metrics(for: mode).map { NSTouchBarItem.Identifier(Self.metricItemPrefix + $0.rawValue) }
            + [.flexibleSpace]
            + (monitor.snapshot.battery.isAvailable ? [Self.batteryItem] : [])
            + [Self.resizeItem]
            + (mode == .fullscreen ? [Self.dashboardItem] : [])
            + [Self.collapseItem]
        return bar
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        switch identifier {
        case Self.collapseItem:
            return button(
                identifier: identifier,
                symbol: "xmark",
                accessibilityDescription: "Collapse GlassDeck",
                action: #selector(collapseFromTouchBar)
            )
        case Self.resizeItem:
            return button(
                identifier: identifier,
                symbol: mode == .fullscreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                accessibilityDescription: mode == .fullscreen ? "Leave full width" : "Use the full Touch Bar",
                action: #selector(toggleFullscreen)
            )
        case Self.batteryItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            batteryView.battery = monitor.snapshot.battery
            item.view = batteryView
            return item
        case Self.dashboardItem:
            let item = button(
                identifier: identifier,
                symbol: "rectangle.on.rectangle",
                accessibilityDescription: "Open the dashboard",
                action: #selector(openDashboard)
            )
            if let control = item.view as? NSButton {
                // Icon only: a titled button costs ~110 pt, which is one metric
                // panel's worth of space and would push the controls off the bar.
                control.title = ""
                control.imagePosition = .imageOnly
                control.bezelColor = NSColor(hue: MetricKind.cpu.hue, saturation: 0.55, brightness: 0.55, alpha: 1)
            }
            return item
        default:
            return metricItem(for: identifier)
        }
    }

    private func metricItem(for identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard let kind = MetricKind.allCases.first(where: {
            identifier.rawValue == Self.metricItemPrefix + $0.rawValue
        }) else { return nil }

        let item = NSCustomTouchBarItem(identifier: identifier)
        let view = TouchBarMetricView(kind: kind)
        view.width = mode == .fullscreen ? 124 : 96
        view.snapshot = monitor.snapshot
        view.history = monitor.history(for: kind)
        metricViews[kind] = view
        item.view = view
        return item
    }

    private func button(
        identifier: NSTouchBarItem.Identifier,
        symbol: String,
        accessibilityDescription: String,
        action: Selector
    ) -> NSCustomTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityDescription) ?? NSImage()
        let control = NSButton(image: image, target: self, action: action)
        control.bezelStyle = .rounded
        control.setAccessibilityLabel(accessibilityDescription)
        item.view = control
        return item
    }
}

/// A Touch Bar view that reports taps, used to make the whole strip a button
/// without the chrome an `NSButton` would draw around it.
private final class TouchBarTapView: NSView {
    var onTap: (() -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 186, height: 30))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func touchesBegan(with event: NSEvent) {
        super.touchesBegan(with: event)
        onTap?()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onTap?()
    }
}

/// Detects the Touch Bar panel in the IO registry.
///
/// The Touch Bar's own display publishes a `dfr` property; matching on it is
/// stable across Intel and Apple silicon MacBook Pros and reports `false` on
/// every Mac that never shipped one.
enum TouchBarHardware {
    static let isPresent: Bool = {
        guard let matching = IOServiceMatching("IOService") as NSMutableDictionary? else { return false }
        matching[kIOPropertyMatchKey] = ["dfr": true] as NSDictionary

        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matching as CFDictionary,
            &iterator
        ) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return false }
        IOObjectRelease(entry)
        return true
    }()
}
