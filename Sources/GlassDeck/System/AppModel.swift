import AppKit
import GlassDeckKit
import Observation
import SwiftUI

/// Wires the sampling engine, the settings store and the Touch Bar together, and
/// owns the two AppKit windows GlassDeck can show.
///
/// The windows are built in AppKit rather than as SwiftUI scenes so that a menu
/// bar-only app can open them from anywhere — including a Touch Bar tap — and so
/// their chrome can be made fully transparent for the glass panel.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let preferences: Preferences
    let monitor: SystemMonitor
    let touchBar: TouchBarController
    /// Drives the clock module and the menu bar clock, on its own once-a-minute
    /// cadence rather than the sampler's.
    let clock = ClockTicker()

    @ObservationIgnored private let alerts: ThresholdAlerts
    /// Mirrors settings changes into the parts of the app that are not SwiftUI views.
    @ObservationIgnored private lazy var preferenceChanges = ObservationLoop(self) { model in
        let preferences = model.preferences
        _ = preferences.refreshInterval
        _ = preferences.isTouchBarEnabled
        _ = preferences.touchBarMetrics
        _ = preferences.panelModules
        _ = preferences.clockZones
        _ = preferences.menuBarClockZone
    } onChange: { model in
        model.monitor.interval = model.preferences.refreshInterval
        model.touchBar.synchroniseWithPreferences()
        model.synchroniseModules()
    }
    @ObservationIgnored private var dashboardWindow: NSWindow?
    @ObservationIgnored private var settingsWindow: NSWindow?
    @ObservationIgnored private var signalSources: [any DispatchSourceSignal] = []
    @ObservationIgnored private var powerObservers: [any NSObjectProtocol] = []

    private init() {
        let preferences = Preferences()
        let monitor = SystemMonitor(interval: preferences.refreshInterval)
        self.preferences = preferences
        self.monitor = monitor
        self.touchBar = TouchBarController(monitor: monitor, preferences: preferences)
        self.alerts = ThresholdAlerts(preferences: preferences, monitor: monitor)
        touchBar.onOpenDashboard = { [weak self] in self?.showDashboard() }
    }

    func start() {
        monitor.start()
        NSApp.touchBar = touchBar.makeApplicationTouchBar()
        touchBar.synchroniseWithPreferences()
        preferenceChanges.start()
        synchroniseModules()
        observePowerEvents()
        alerts.start()
        installSignalHandlers()

        applyDevelopmentOverrides()
    }

    /// A presented system-modal Touch Bar outlives the process that put it there:
    /// if GlassDeck is killed while its bar is up, the Touch Bar stays stuck on a
    /// dead bar until the system's Touch Bar server is restarted. `applicationWillTerminate`
    /// does not run for a signal, so SIGINT and SIGTERM are handled explicitly and
    /// the bar is taken down before exiting.
    /// Parks sampling whenever nothing can be seen: the display asleep, the
    /// machine suspended, or another user switched in front.
    ///
    /// A menu bar that nobody is looking at is still a menu bar being redrawn,
    /// and the SMC round trips behind it are the priciest part of a sample. The
    /// monitor keeps its intent to be running throughout, so the wake path is a
    /// `resume()` rather than a fresh `start()` — which also takes a leading
    /// sample, so the first glance after a wake is not the reading from before
    /// the screen went dark.
    private func observePowerEvents() {
        let center = NSWorkspace.shared.notificationCenter
        let park = [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ]
        let wake = [
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ]

        // Both halves are idempotent, which matters because the events overlap:
        // putting the machine to sleep sends the screens to sleep as well.
        for name in park {
            powerObservers.append(observe(name, on: center) { $0.monitor.suspend() })
        }
        for name in wake {
            powerObservers.append(observe(name, on: center) {
                $0.monitor.resume()
                // The minute the machine slept through has passed: the ticker's
                // own sleep fires on its own, but not before the first glance.
                $0.clock.refresh()
            })
        }
    }

    private func observe(
        _ name: NSNotification.Name,
        on center: NotificationCenter,
        perform action: @escaping @MainActor (AppModel) -> Void
    ) -> any NSObjectProtocol {
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                action(self)
            }
        }
    }

    private func installSignalHandlers() {
        for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                self?.touchBar.shutDown()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    /// Neither the Touch Bar nor a menu bar extra can be driven by scripted
    /// clicks, so two environment variables let a build come up in a given state
    /// for screenshots and manual testing:
    /// `GLASSDECK_TOUCHBAR_MODE=fullscreen|expanded|mini|detail:<metric>`,
    /// `GLASSDECK_OPEN_DASHBOARD=1`, `GLASSDECK_OPEN_SETTINGS=1` and
    /// `GLASSDECK_OPEN_PANEL=1`, which puts the
    /// menu bar panel in an ordinary window: a `MenuBarExtra` cannot be opened
    /// any other way, so without it the panel is the one surface that cannot be
    /// looked at except by hand.
    private func applyDevelopmentOverrides() {
        let environment = ProcessInfo.processInfo.environment

        switch environment["GLASSDECK_TOUCHBAR_MODE"] {
        case "fullscreen": touchBar.present(.fullscreen)
        case "expanded": touchBar.present(.expanded)
        case "mini": touchBar.present(.mini)
        case let requested? where requested.hasPrefix("detail:"):
            let kind = MetricKind(rawValue: String(requested.dropFirst("detail:".count)))
            Task { @MainActor in
                // Wait for a sample so hardware-dependent metrics are known.
                try? await Task.sleep(for: .seconds(2))
                kind.map(self.touchBar.expand)
            }
        default: break
        }

        if environment["GLASSDECK_OPEN_DASHBOARD"] == "1" {
            showDashboard()
        }

        if environment["GLASSDECK_OPEN_PANEL"] == "1" {
            showPanel()
        }

        if environment["GLASSDECK_OPEN_SETTINGS"] == "1" {
            showSettings()
        }

    }

    /// Tears everything down on quit *without* touching stored settings: writing
    /// preferences here meant a single quit left the Touch Bar switched off for
    /// every later launch.
    func stop() {
        monitor.stop()
        touchBar.shutDown()

        let center = NSWorkspace.shared.notificationCenter
        powerObservers.forEach(center.removeObserver)
        powerObservers.removeAll()
    }

    // MARK: - Windows

    func showDashboard() {
        show(\.dashboardWindow) {
            makeGlassWindow(title: "GlassDeck", size: NSSize(width: 720, height: 560), content: DashboardView())
        }
    }

    func showSettings() {
        show(\.settingsWindow) {
            makeGlassWindow(
                title: String(localized: "GlassDeck Settings"),
                size: NSSize(width: 460, height: 330),
                content: SettingsView(),
                isResizable: false,
                isTransparent: false
            )
        }
    }

    /// The menu bar panel in a window of its own. Only reachable through the
    /// development override above, and built afresh each time rather than kept.
    func showPanel() {
        bringForward(makeGlassWindow(
            title: "GlassDeck",
            size: NSSize(width: Theme.panelWidth, height: 900),
            content: GlassPanelView(),
            isResizable: false
        ))
    }

    /// Brings back the window kept in `slot`, building it the first time.
    private func show(_ slot: ReferenceWritableKeyPath<AppModel, NSWindow?>, make: () -> NSWindow) {
        if let window = self[keyPath: slot] { return bringForward(window) }
        let window = make()
        self[keyPath: slot] = window
        bringForward(window)
    }

    private func bringForward(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A centred window hosting `content`, with the app's environment injected.
    ///
    /// Kept rather than released when it closes, so reopening it is a matter of
    /// ordering it back in.
    private func makeGlassWindow(
        title: String,
        size: NSSize,
        content: some View,
        isResizable: Bool = true,
        isTransparent: Bool = true
    ) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if isResizable { style.insert(.resizable) }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: content.appEnvironment(self))
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false

        if isTransparent {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = .clear
            window.isOpaque = false
        }
        window.center()
        return window
    }

    // MARK: - Settings plumbing

    /// Brings the two modules' costs in line with whether they are switched on.
    ///
    /// The ticker runs only while a clock is actually on screen — nobody starts
    /// out with one, so a default install schedules nothing — and the Bluetooth
    /// stack is not asked anything at all until the card exists, because the
    /// asking is what raises the permission prompt.
    private func synchroniseModules() {
        let onCard = preferences.panelModules.contains(.clock) && !preferences.clockZones.isEmpty
        clock.setWanted(onCard || preferences.menuBarClockZone != nil)
        monitor.samplesBluetooth = preferences.panelModules.contains(.bluetooth)
    }
}

extension View {
    /// Everything GlassDeck's views read from the environment. A view that has
    /// no use for one of these takes no dependency on it.
    func appEnvironment(_ model: AppModel) -> some View {
        environment(model)
            .environment(model.monitor)
            .environment(model.preferences)
            .environment(model.clock)
            .environment(model.touchBar)
    }
}
