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
        /// Nothing presented: the Touch Bar belongs to the system and the
        /// frontmost app again.
        case collapsed
        /// Just the compact meter, so GlassDeck never disappears entirely.
        case mini
        case expanded
        case fullscreen

        /// Placement passed to the system: `0` keeps the Control Strip, `1` covers it.
        var placement: Int { self == .fullscreen ? 1 : 0 }

        /// One step smaller. Shrinking stops at `mini` rather than at nothing.
        var smaller: Mode {
            switch self {
            case .fullscreen: .expanded
            case .expanded, .mini, .collapsed: .mini
            }
        }

        /// One step larger.
        var larger: Mode {
            switch self {
            case .collapsed, .mini: .expanded
            case .expanded, .fullscreen: .fullscreen
            }
        }
    }

    static let controlStripIdentifier = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.controlstrip")
    private static let barIdentifier = NSTouchBar.CustomizationIdentifier("dev.fracata00.glassdeck.bar")
    private static let collapseItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.collapse")
    private static let resizeItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.resize")
    private static let dashboardItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.dashboard")
    private static let batteryItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.battery")
    private static let metricItemPrefix = "dev.fracata00.glassdeck.metric."
    private static let miniMeterItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.mini")
    private static let leadingSpacerItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.spacer")

    /// Room a bar presented at placement 0 has beside the system Control Strip,
    /// measured on a 13-inch MacBook Pro with the system close box showing.
    ///
    /// The bar sizes itself to its content: ask for more and the trailing items
    /// are clipped, so panels are sized to fit this budget and alignment uses a
    /// spacer only as wide as the leftover space.
    private static let sharedRegionWidth: CGFloat = 540

    /// Usable width when GlassDeck owns the whole bar.
    private static let fullRegionWidth: CGFloat = 1004
    private static let itemSpacing: CGFloat = 8
    /// Pinned width of the shrink, grow and dashboard buttons.
    private static let controlWidth: CGFloat = 46

    /// True when this Mac actually has a Touch Bar and the private hooks resolved.
    let isSupported: Bool

    private(set) var mode: Mode = .collapsed

    private let monitor: SystemMonitor
    private let preferences: Preferences
    private let stripView = TouchBarStripView()
    /// A second meter instance: the Control Strip one is owned by the tray item,
    /// and a view cannot live in two places at once.
    private let miniStripView = TouchBarStripView()
    private let tapView = TouchBarTapView()
    private var stripItem: NSCustomTouchBarItem?
    private var presentedBar: NSTouchBar?
    private var metricViews: [MetricKind: TouchBarMetricView] = [:]
    private let batteryView = TouchBarBatteryView()
    private var activationObserver: NSObjectProtocol?
    private var presentedSignature: String?
    /// Set when the user releases the Touch Bar from the bar itself. It lasts for
    /// the session only — a tap is not a settings change, so nothing is persisted.
    private var isReleasedForSession = false
    /// Width of the spacer that shifts the bar towards the Control Strip.
    private var leadingSpacerWidth: CGFloat = 0
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
            if mode == .collapsed, !isReleasedForSession { present(.expanded) }
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

    /// Called on quit: releases the Touch Bar and removes the tray item without
    /// changing anything the user has configured.
    func shutDown() {
        stopReasserting()
        if let presentedBar {
            SystemTouchBar.dismissSystemModal(presentedBar)
            self.presentedBar = nil
            presentedSignature = nil
            mode = .collapsed
        }
        if let stripItem {
            DFRSupport.setControlStripPresence(Self.controlStripIdentifier, visible: false)
            SystemTouchBar.removeSystemTrayItem(stripItem)
            self.stripItem = nil
        }
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

    /// Tapping the Control Strip meter opens the bar — and brings GlassDeck back
    /// after it was released — while a second tap shrinks it again.
    private func handleStripTap() {
        if mode == .collapsed {
            isReleasedForSession = false
            present(.expanded)
        } else {
            present(.mini)
        }
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

    /// The shrink button. It steps down one size at a time and stops at the
    /// compact meter, so a single tap can never make GlassDeck vanish; only a tap
    /// on the already-minimal bar hands the Touch Bar back.
    @objc private func shrink() {
        if mode == .mini {
            isReleasedForSession = true
            collapse()
        } else {
            present(mode.smaller)
        }
    }

    @objc private func grow() {
        present(mode.larger)
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
                      self.preferences.touchBarPresentation == .alwaysOn,
                      !self.isReleasedForSession
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
        miniStripView.snapshot = snapshot
        batteryView.battery = snapshot.battery
        if mode == .fullscreen { batteryView.power = snapshot.power }
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
            _ = preferences.touchBarAlignment
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stripView.metrics = self.preferences.touchBarMetrics
                self.miniStripView.metrics = self.preferences.touchBarMetrics
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
        guard mode != .mini else { return [] }

        // Battery rides in the chip on the right, and power rides along with it.
        var metrics = preferences.touchBarMetrics.filter { $0 != .battery && $0 != .power }

        guard mode == .fullscreen else {
            // Sharing the bar with the Control Strip leaves roughly 540 pt: four
            // narrow panels plus the controls is the most that stays legible.
            return Array(metrics.filter { $0 != .fans && $0 != .temperature }.prefix(4))
        }

        // Hardware readings that only full width has room for, appended in the
        // order they earn their place.
        for extra in [MetricKind.fans, .temperature] where !metrics.contains(extra) {
            if monitor.snapshot.supports(extra) { metrics.append(extra) }
        }
        metrics = metrics.filter { monitor.snapshot.supports($0) }

        let controls = (monitor.snapshot.battery.isAvailable ? batteryView.intrinsicContentSize.width + Self.itemSpacing : 0)
            + 3 * (Self.controlWidth + Self.itemSpacing)
        let room = Self.fullRegionWidth - controls
        let fitting = max(1, Int(room / (metricPanelWidth(for: mode) + Self.itemSpacing)))
        return Array(metrics.prefix(fitting))
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
        return "\(mode)|\(metrics)|battery:\(monitor.snapshot.battery.isAvailable)|align:\(preferences.touchBarAlignment.rawValue)"
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
        let content: [NSTouchBarItem.Identifier] = mode == .mini
            ? [Self.miniMeterItem, Self.resizeItem, Self.collapseItem]
            : metrics(for: mode).map { NSTouchBarItem.Identifier(Self.metricItemPrefix + $0.rawValue) }
                + (monitor.snapshot.battery.isAvailable ? [Self.batteryItem] : [])
                + [Self.resizeItem]
                + (mode == .fullscreen ? [Self.dashboardItem] : [])
                + [Self.collapseItem]

        // Full width has nowhere to move to; the other sizes honour the alignment
        // setting, with flexible spaces doing the pushing.
        bar.defaultItemIdentifiers = mode == .fullscreen
            ? content
            : aligned(content, for: mode)
        return bar
    }

    private func aligned(_ content: [NSTouchBarItem.Identifier], for mode: Mode) -> [NSTouchBarItem.Identifier] {
        let slack = Self.sharedRegionWidth - contentWidth(of: content, for: mode)
        guard slack > 24, preferences.touchBarAlignment != .leading else {
            // A full bar cannot be moved; forcing it would push items under the
            // Control Strip, where the system clips them.
            return content + [.flexibleSpace]
        }

        leadingSpacerWidth = preferences.touchBarAlignment == .center ? slack / 2 : slack
        return [Self.leadingSpacerItem] + content
    }

    /// Measured width of the items, used to work out how far they can shift.
    private func contentWidth(of content: [NSTouchBarItem.Identifier], for mode: Mode) -> CGFloat {
        var width: CGFloat = 0
        for identifier in content {
            switch identifier {
            case Self.miniMeterItem: width += miniStripView.intrinsicContentSize.width
            case Self.batteryItem: width += batteryView.intrinsicContentSize.width
            case Self.resizeItem, Self.collapseItem, Self.dashboardItem: width += Self.controlWidth
            default: width += metricPanelWidth(for: mode)
            }
        }
        return width + CGFloat(content.count - 1) * Self.itemSpacing
    }

    private func metricPanelWidth(for mode: Mode) -> CGFloat {
        mode == .fullscreen ? 108 : 84
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        switch identifier {
        case Self.leadingSpacerItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = FixedWidthSpacer(width: leadingSpacerWidth)
            return item
        case Self.miniMeterItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            miniStripView.metrics = preferences.touchBarMetrics
            miniStripView.snapshot = monitor.snapshot
            item.view = miniStripView
            return item
        case Self.collapseItem:
            return button(
                identifier: identifier,
                symbol: mode == .mini ? "xmark" : "chevron.compact.down",
                accessibilityDescription: mode == .mini
                    ? "Hand the Touch Bar back until the Control Strip meter is tapped"
                    : "Shrink GlassDeck",
                action: #selector(shrink)
            )
        case Self.resizeItem:
            return button(
                identifier: identifier,
                symbol: mode == .fullscreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                accessibilityDescription: mode == .fullscreen ? "Leave full width" : "Use the full Touch Bar",
                action: #selector(grow)
            )
        case Self.batteryItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            batteryView.battery = monitor.snapshot.battery
            // Full width has room to spell out the draw next to the charge.
            batteryView.power = mode == .fullscreen ? monitor.snapshot.power : .unavailable
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
        view.width = metricPanelWidth(for: mode)
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
        // A bezelled button sizes itself to about 75 pt, which is a metric panel's
        // worth of space per button; pinning the width keeps the layout inside the
        // budget the bar actually grants.
        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: Self.controlWidth).isActive = true
        item.view = control
        return item
    }
}

/// An invisible view of a fixed width, used to reserve the Control Strip's area.
private final class FixedWidthSpacer: NSView {
    private let width: CGFloat

    init(width: CGFloat) {
        self.width = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: width, height: 30) }
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
