import AppKit
import Foundation
import GlassDeckKit
import UserNotifications

/// Notifies when the machine runs hotter than the user asked to be told about,
/// or when the kernel reports that memory is running short.
///
/// Driven from `coarseSnapshot` rather than every sample: a thermometer that is
/// itself only read every few seconds gains nothing from being checked more
/// often, and this way the check costs nothing on the ticks in between.
@MainActor
final class ThresholdAlerts {
    /// How far the temperature has to fall before the same alert can fire again.
    ///
    /// Without it a reading sitting on the threshold would notify, drop a tenth
    /// of a degree, and notify again — for as long as the machine stayed there.
    private static let releaseMargin = 5.0

    private let preferences: Preferences
    private let monitor: SystemMonitor

    private var isAlerting = false
    /// The highest pressure already notified about. A notification goes out
    /// when the pressure climbs past it, so high then critical is two alerts
    /// but a level that flickers is one; it resets once pressure is back to normal.
    private var notifiedPressure = MemoryPressure.normal
    private lazy var changes = ObservationLoop(self) { alerts in
        _ = alerts.monitor.coarseSnapshot
    } onChange: { alerts in
        alerts.check(alerts.monitor.coarseSnapshot)
    }

    init(preferences: Preferences, monitor: SystemMonitor) {
        self.preferences = preferences
        self.monitor = monitor
    }

    func start() {
        changes.start()
    }

    /// Asks for permission at the moment the user turns the alert on, rather
    /// than at launch for something they may never enable.
    static func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                NSLog("GlassDeck: notification permission denied – \(error.localizedDescription)")
            }
        }
    }

    private func check(_ snapshot: MetricsSnapshot) {
        checkTemperature(snapshot)
        checkMemory(snapshot.memory)
    }

    private func checkMemory(_ memory: MemoryUsage) {
        guard preferences.isMemoryPressureAlertEnabled else {
            notifiedPressure = .normal
            return
        }
        if memory.pressureLevel == .normal {
            notifiedPressure = .normal
        } else if memory.pressureLevel > notifiedPressure {
            notifiedPressure = memory.pressureLevel
            postMemory(memory)
        }
    }

    private func postMemory(_ memory: MemoryUsage) {
        let body = memory.pressureLevel == .critical
            ? String(localized: "Memory pressure is critical. Quit an app or close some tabs before the Mac slows to a crawl.")
            : String(
                format: String(localized: "Memory pressure is high: the Mac is compressing memory and using swap (%@)."),
                ValueFormatter.bytes(memory.swapUsed)
            )
        post(identifier: "dev.fracata00.glassdeck.memory", body: body)
    }

    private func checkTemperature(_ snapshot: MetricsSnapshot) {
        guard preferences.isTemperatureAlertEnabled, let hottest = snapshot.thermal.hottest else {
            isAlerting = false
            return
        }

        let threshold = preferences.temperatureThreshold
        if !isAlerting, hottest >= threshold {
            isAlerting = true
            post(hottest: hottest, threshold: threshold)
        } else if isAlerting, hottest < threshold - Self.releaseMargin {
            isAlerting = false
        }
    }

    private func post(hottest: Double, threshold: Double) {
        post(
            identifier: "dev.fracata00.glassdeck.temperature",
            body: String(
                format: String(localized: "Running hot: %1$lld°C, above the %2$lld°C you asked about."),
                Int(hottest.rounded()),
                Int(threshold.rounded())
            )
        )
    }

    private func post(identifier: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }

        let content = UNMutableNotificationContent()
        content.title = "GlassDeck"
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("GlassDeck: could not post the alert \(identifier) – \(error.localizedDescription)")
            }
        }
    }
}
