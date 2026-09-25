import AppKit
import GlassDeckKit
import SwiftUI

/// GlassDeck lives in the menu bar: a Liquid Glass panel for the details, a
/// Control Strip meter for the glance, and no Dock icon.
@main
struct GlassDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            GlassPanelView()
                .appEnvironment(model)
        } label: {
            MenuBarLabel(monitor: model.monitor, preferences: model.preferences, clock: model.clock)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The status item content, redrawn on every sample.
private struct MenuBarLabel: View {
    @Bindable var monitor: SystemMonitor
    @Bindable var preferences: Preferences
    @Bindable var clock: ClockTicker

    var body: some View {
        HStack(spacing: 6) {
            if let clock = menuBarClock {
                Text(clock)
                    .monospacedDigit()
            }
            meter
        }
    }

    /// The clock in the status item, or `nil` when nobody asked for one.
    ///
    /// Named rather than bare when it is somewhere else — a lone `21:32` beside
    /// a Mac reading 14:32 is a puzzle — and bare when the zone is this one.
    /// The guards run before `clock.now` is touched, so an install with no menu
    /// bar clock never takes a dependency on the ticker and never redraws the
    /// status item for it.
    private var menuBarClock: String? {
        guard let identifier = preferences.menuBarClockZone,
              let timeZone = TimeZone(identifier: identifier)
        else { return nil }

        let time = WorldClock.time(in: timeZone, at: clock.now)
        guard identifier != TimeZone.current.identifier else { return time }
        let label = preferences.clockZones.first { $0.identifier == identifier }?.displayLabel
            ?? ClockZone.cityName(for: identifier)
        return "\(label) \(time)"
    }

    @ViewBuilder
    private var meter: some View {
        // Reads `coarseSnapshot`, never `snapshot`: redrawing the status item is
        // the app's largest single cost, and this body re-runs — and the status
        // item redraws — on every property it touches that changes.
        switch preferences.menuBarStyle {
        case .graph:
            Image(nsImage: MenuBarGlyph.bars(for: monitor.coarseSnapshot, metrics: preferences.dashboardMetrics))
        case .percentage:
            // A metric stored before the hardware was known — fans on a fanless
            // Mac — would otherwise sit in the menu bar reading n/a for good.
            let metric = monitor.coarseSnapshot.supports(preferences.menuBarMetric)
                ? preferences.menuBarMetric : .cpu
            HStack(spacing: 3) {
                Image(systemName: metric.symbolName)
                Text(monitor.coarseSnapshot.headline(for: metric))
                    .monospacedDigit()
            }
        case .icon:
            Image(systemName: "gauge.with.dots.needle.67percent")
        }
    }
}

/// Menu bar apps still need a delegate: it sets the activation policy, starts the
/// sampler, and tears the Control Strip item down on quit so it does not linger.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
