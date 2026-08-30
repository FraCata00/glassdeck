import AppKit
import Foundation
import GlassDeckKit
import Observation
import UserNotifications

/// Notifies when the machine runs hotter than the user asked to be told about.
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
    private var isObserving = false

    init(preferences: Preferences, monitor: SystemMonitor) {
        self.preferences = preferences
        self.monitor = monitor
    }

    func start() {
        guard !isObserving else { return }
        isObserving = true
        observe()
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

    private func observe() {
        withObservationTracking {
            _ = monitor.coarseSnapshot
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.check(self.monitor.coarseSnapshot)
                self.observe()
            }
        }
    }

    private func check(_ snapshot: MetricsSnapshot) {
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
        guard Bundle.main.bundleIdentifier != nil else { return }

        let content = UNMutableNotificationContent()
        content.title = "GlassDeck"
        content.body = String(
            format: String(localized: "Running hot: %1$lld°C, above the %2$lld°C you asked about."),
            Int(hottest.rounded()),
            Int(threshold.rounded())
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "dev.fracata00.glassdeck.temperature",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("GlassDeck: could not post the temperature alert – \(error.localizedDescription)")
            }
        }
    }
}
