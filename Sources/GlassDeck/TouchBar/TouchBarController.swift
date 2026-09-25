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
    typealias Mode = TouchBarMode

    static let controlStripIdentifier = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.controlstrip")
    private static let barIdentifier = NSTouchBar.CustomizationIdentifier("dev.fracata00.glassdeck.bar")
    private static let collapseItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.collapse")
    private static let resizeItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.resize")
    private static let dashboardItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.dashboard")
    private static let batteryItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.battery")
    private static let metricItemPrefix = "dev.fracata00.glassdeck.metric."
    private static let miniMeterItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.mini")
    private static let detailItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.detail")
    private static let backItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.back")
    private static let applicationMeterItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.appmeter")
    private static let leadingSpacerItem = NSTouchBarItem.Identifier("dev.fracata00.glassdeck.spacer")

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
    private let applicationTapView = TouchBarTapView()
    private var stripItem: NSCustomTouchBarItem?
    private var presentedBar: NSTouchBar?
    private var metricViews: [MetricKind: TouchBarMetricView] = [:]
    private let batteryView = TouchBarBatteryView()
    private let detailView = TouchBarDetailView(width: 856)
    /// Shown by the system whenever GlassDeck itself is frontmost and no bar of
    /// its own is presented — without it the Touch Bar would simply go black,
    /// because a menu bar app defines no Touch Bar of its own.
    private let applicationStripView = TouchBarStripView()
    /// The size to return to when the expanded metric is dismissed.
    private var modeBeforeDetail: Mode = .fullscreen
    private var activationObserver: NSObjectProtocol?
    /// What the presented bar was built from; `nil` while nothing is presented.
    private var presentedLayout: TouchBarLayout?
    /// Set when the user releases the Touch Bar from the bar itself. It lasts for
    /// the session only — a tap is not a settings change, so nothing is persisted.
    private var isReleasedForSession = false
    /// Bridges the Observation framework to AppKit: redraws the bar whenever a
    /// reading or a Touch Bar setting it shows changes.
    ///
    /// Only one of the two snapshots is read, and that is the whole point:
    /// `@Observable` tracks each property separately, so a bar that reads the
    /// coarse republication is not invalidated by the sample in between. The
    /// mode is read too, so a bar that has just grown is re-armed against the
    /// fine cadence straight away rather than spending its first seconds at the
    /// coarse rate the mini bar left behind.
    @ObservationIgnored private lazy var changes = ObservationLoop(self) { controller in
        _ = controller.mode.wantsFineCadence
            ? controller.monitor.snapshot
            : controller.monitor.coarseSnapshot
        _ = controller.preferences.touchBarMetrics
        _ = controller.preferences.touchBarAlignment
    } onChange: { controller in
        controller.applyMetricsToStrips()
        controller.rebuildBarIfNeeded()
        controller.refresh()
    }

    /// Called when the user asks for the full dashboard from the Touch Bar.
    var onOpenDashboard: (() -> Void)?

    init(monitor: SystemMonitor, preferences: Preferences) {
        self.monitor = monitor
        self.preferences = preferences
        self.isSupported = TouchBarHardware.isPresent && DFRSupport.isAvailable
        super.init()

        applyMetricsToStrips()
        stripView.frame = tapView.bounds
        stripView.autoresizingMask = [.width, .height]
        tapView.addSubview(stripView)
        tapView.onTap = { [weak self] in self?.handleStripTap() }
        batteryView.onTap = { [weak self] in self?.expand(.battery) }
        detailView.onTap = { [weak self] in self?.dismissDetail() }
        applicationTapView.onTap = { [weak self] in self?.present(.expanded) }
        applicationStripView.frame = applicationTapView.bounds
        applicationStripView.autoresizingMask = [.width, .height]
        applicationTapView.addSubview(applicationStripView)
    }

    // MARK: - Lifecycle

    /// Installs or removes the Control Strip item and applies the presentation
    /// mode. Safe to call whenever settings change.
    func synchroniseWithPreferences() {
        guard isSupported else { return }

        guard preferences.isTouchBarEnabled else {
            shutDown()
            return
        }

        install()
        applyMetricsToStrips()
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

    /// The app's own Touch Bar, used by the system when GlassDeck is frontmost.
    func makeApplicationTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [.flexibleSpace, Self.applicationMeterItem, .flexibleSpace]
        return bar
    }

    private func install() {
        guard stripItem == nil else { return }
        DFRSupport.setSystemModalShowsCloseBox(true)

        let item = NSCustomTouchBarItem(identifier: Self.controlStripIdentifier)
        item.view = tapView
        stripItem = item

        SystemTouchBar.addSystemTrayItem(item)
        DFRSupport.setControlStripPresence(Self.controlStripIdentifier, visible: true)
        changes.start()
    }

    /// Releases the Touch Bar and removes the tray item without changing
    /// anything the user has configured. Called on quit and when the Touch Bar
    /// is switched off in settings.
    func shutDown() {
        stopReasserting()
        dismissPresentedBar()
        guard let stripItem else { return }
        DFRSupport.setControlStripPresence(Self.controlStripIdentifier, visible: false)
        SystemTouchBar.removeSystemTrayItem(stripItem)
        self.stripItem = nil
    }

    /// Takes the presented bar down, if there is one, and records that nothing
    /// is presented any more.
    private func dismissPresentedBar() {
        guard let presentedBar else { return }
        SystemTouchBar.dismissSystemModal(presentedBar)
        self.presentedBar = nil
        presentedLayout = nil
        mode = .collapsed
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
        dismissPresentedBar()

        // Switching between expanded and fullscreen changes both the item list
        // and the placement, so the bar is rebuilt rather than re-presented as is.
        // Recorded before the bar is built: the delegate reads the layout for the
        // spacer and panel widths whenever it is asked for an item.
        let layout = layout(for: newMode)
        presentedLayout = layout
        mode = newMode
        let bar = makeBar(for: layout)
        presentedBar = bar
        SystemTouchBar.presentSystemModal(bar, identifier: Self.controlStripIdentifier, placement: newMode.placement)
        refresh()
    }

    /// Returns the Touch Bar to the system, leaving the Control Strip meter behind.
    func collapse() {
        guard presentedBar != nil, mode != .collapsed else { return }
        dismissPresentedBar()
    }

    /// Expands a single metric across the bar. Tapping a panel is how the extra
    /// numbers are reached without crowding the compact layouts.
    func expand(_ kind: MetricKind) {
        guard isSupported else { return }
        // Before the first sample nothing is known to be supported yet; the panel
        // that was tapped is proof enough that the metric exists.
        guard monitor.snapshot.supports(kind) || monitor.snapshot == .empty else { return }
        if mode.expandedMetric == nil { modeBeforeDetail = mode }
        present(.detail(kind))
    }

    @objc private func dismissDetail() {
        present(modeBeforeDetail == .collapsed ? .expanded : modeBeforeDetail)
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
        applicationStripView.snapshot = snapshot
        batteryView.battery = snapshot.battery
        if let kind = mode.expandedMetric {
            detailView.snapshot = snapshot
            detailView.history = monitor.history(for: kind)
        }
        for (kind, view) in metricViews {
            view.snapshot = snapshot
            view.history = monitor.history(for: kind)
        }
    }

    // MARK: - Bar construction

    /// The three meters all show the Touch Bar selection. Kept in step here,
    /// ahead of any layout, because the mini meter's width depends on it.
    private func applyMetricsToStrips() {
        let metrics = preferences.touchBarMetrics
        stripView.metrics = metrics
        miniStripView.metrics = metrics
        applicationStripView.metrics = metrics
    }

    private func layout(for mode: Mode) -> TouchBarLayout {
        let snapshot = monitor.snapshot
        return TouchBarLayout(
            mode: mode,
            selection: preferences.touchBarMetrics,
            order: preferences.metricOrder,
            supported: Set(MetricKind.allCases.filter(snapshot.supports)),
            hasBattery: snapshot.battery.isAvailable,
            alignment: preferences.touchBarAlignment,
            batteryWidth: batteryView.intrinsicContentSize.width,
            miniMeterWidth: miniStripView.intrinsicContentSize.width
        )
    }

    /// The bar is built before the first sample lands, so battery and fan
    /// availability are unknown at that point. The layout is worked out again
    /// here and the bar rebuilt once it changes — otherwise the battery chip
    /// would stay missing for the whole session.
    private func rebuildBarIfNeeded() {
        guard mode != .collapsed, layout(for: mode) != presentedLayout else { return }
        present(mode)
    }

    private func makeBar(for layout: TouchBarLayout) -> NSTouchBar {
        metricViews.removeAll()

        let bar = NSTouchBar()
        bar.delegate = self
        bar.customizationIdentifier = Self.barIdentifier
        bar.defaultItemIdentifiers = layout.items.map(identifier(for:))
        return bar
    }

    private func identifier(for item: TouchBarLayout.Item) -> NSTouchBarItem.Identifier {
        switch item {
        case .leadingSpacer: Self.leadingSpacerItem
        case .flexibleSpace: .flexibleSpace
        case let .metric(kind): NSTouchBarItem.Identifier(Self.metricItemPrefix + kind.rawValue)
        case .battery: Self.batteryItem
        case .grow: Self.resizeItem
        case .dashboard: Self.dashboardItem
        case .collapse: Self.collapseItem
        case .miniMeter: Self.miniMeterItem
        case .back: Self.backItem
        case .detail: Self.detailItem
        }
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        switch identifier {
        case Self.leadingSpacerItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = FixedWidthSpacer(width: presentedLayout?.leadingSpacerWidth ?? 0)
            return item
        case Self.backItem:
            return button(
                identifier: identifier,
                symbol: "chevron.backward",
                accessibilityDescription: String(localized: "Back to the meters"),
                action: #selector(dismissDetail)
            )
        case Self.detailItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            if let kind = mode.expandedMetric {
                detailView.kind = kind
                detailView.snapshot = monitor.snapshot
                detailView.history = monitor.history(for: kind)
            }
            item.view = detailView
            return item
        case Self.applicationMeterItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            applicationStripView.metrics = preferences.touchBarMetrics
            applicationStripView.snapshot = monitor.snapshot
            item.view = applicationTapView
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
                    ? String(localized: "Hand the Touch Bar back until the Control Strip meter is tapped")
                    : String(localized: "Shrink GlassDeck"),
                action: #selector(shrink)
            )
        case Self.resizeItem:
            // Only ever means "grow": the bar drops this item in full width.
            return button(
                identifier: identifier,
                symbol: "arrow.up.left.and.arrow.down.right",
                accessibilityDescription: String(localized: "Use the full Touch Bar"),
                action: #selector(grow)
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
                accessibilityDescription: String(localized: "Open the dashboard"),
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
        view.width = presentedLayout?.panelWidth ?? TouchBarLayout.minimumPanelWidth
        view.snapshot = monitor.snapshot
        view.history = monitor.history(for: kind)
        view.onTap = { [weak self] in self?.expand(kind) }
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
        control.widthAnchor.constraint(equalToConstant: TouchBarLayout.controlWidth).isActive = true
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
