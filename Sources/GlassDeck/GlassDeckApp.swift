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
                .environment(model.monitor)
                .environment(model.preferences)
                .environment(model)
        } label: {
            MenuBarLabel(monitor: model.monitor, preferences: model.preferences)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The status item content, redrawn on every sample.
private struct MenuBarLabel: View {
    @Bindable var monitor: SystemMonitor
    @Bindable var preferences: Preferences

    var body: some View {
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
