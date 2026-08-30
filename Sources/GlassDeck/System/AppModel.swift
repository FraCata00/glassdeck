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

    @ObservationIgnored private var dashboardWindow: NSWindow?
    @ObservationIgnored private var settingsWindow: NSWindow?
    @ObservationIgnored private var signalSources: [any DispatchSourceSignal] = []

    private init() {
        let preferences = Preferences()
        let monitor = SystemMonitor(interval: preferences.refreshInterval)
        self.preferences = preferences
        self.monitor = monitor
        self.touchBar = TouchBarController(monitor: monitor, preferences: preferences)
        touchBar.onOpenDashboard = { [weak self] in self?.showDashboard() }
    }

    func start() {
        monitor.start()
        touchBar.synchroniseWithPreferences()
        observePreferences()
        installSignalHandlers()

        applyDevelopmentOverrides()
    }

    /// A presented system-modal Touch Bar outlives the process that put it there:
    /// if GlassDeck is killed while its bar is up, the Touch Bar stays stuck on a
    /// dead bar until the system's Touch Bar server is restarted. `applicationWillTerminate`
    /// does not run for a signal, so SIGINT and SIGTERM are handled explicitly and
    /// the bar is taken down before exiting.
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
    /// `GLASSDECK_TOUCHBAR_MODE=fullscreen|expanded|mini` and `GLASSDECK_OPEN_DASHBOARD=1`.
    private func applyDevelopmentOverrides() {
        let environment = ProcessInfo.processInfo.environment

        switch environment["GLASSDECK_TOUCHBAR_MODE"] {
        case "fullscreen": touchBar.present(.fullscreen)
        case "expanded": touchBar.present(.expanded)
        case "mini": touchBar.present(.mini)
        default: break
        }

        if environment["GLASSDECK_OPEN_DASHBOARD"] == "1" {
            showDashboard()
        }

    }

    /// Tears everything down on quit *without* touching stored settings: writing
    /// preferences here meant a single quit left the Touch Bar switched off for
    /// every later launch.
    func stop() {
        monitor.stop()
        touchBar.shutDown()
    }

    // MARK: - Windows

    func showDashboard() {
        if let dashboardWindow {
            dashboardWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = makeGlassWindow(
            title: "GlassDeck",
            size: NSSize(width: 720, height: 560),
            content: DashboardView().environment(monitor).environment(preferences).environment(self)
        )
        window.isReleasedWhenClosed = false
        dashboardWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = makeGlassWindow(
            title: "GlassDeck Settings",
            size: NSSize(width: 460, height: 330),
            content: SettingsView().environment(preferences).environment(touchBar),
            isResizable: false,
            isTransparent: false
        )
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

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
        window.contentView = NSHostingView(rootView: content)
        window.isMovableByWindowBackground = true

        if isTransparent {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = .clear
            window.isOpaque = false
        }
        return window
    }

    // MARK: - Settings plumbing

    /// Mirrors settings changes into the parts of the app that are not SwiftUI views.
    private func observePreferences() {
        withObservationTracking {
            _ = preferences.refreshInterval
            _ = preferences.isTouchBarEnabled
            _ = preferences.touchBarMetrics
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.monitor.interval = self.preferences.refreshInterval
                self.touchBar.synchroniseWithPreferences()
                self.observePreferences()
            }
        }
    }
}
