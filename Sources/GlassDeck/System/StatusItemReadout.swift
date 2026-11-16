import GlassDeckKit
import Observation

/// What the status item shows, published only when it would look different.
///
/// Redrawing the status item is the app's largest single cost — profiling a
/// running build put it at more than half of everything the main thread did,
/// because AppKit re-renders the item once for every copy of the menu bar it
/// keeps. A snapshot is new on every publication by its timestamp alone, so a
/// label that read the snapshot itself was redrawn each time whether or not a
/// single pixel had changed: a temperature holding at 54°, a battery at 80%,
/// bars that had moved by less than the bar chart can show.
///
/// This sits between the two. It reads the coarse snapshot, reduces it to
/// exactly what the label draws, and assigns that only when it differs from
/// what is already up — and `@Observable` then has nothing to tell the label.
///
/// With the real-time setting on it reads the fine snapshot instead, so the
/// label shows exactly what the panel shows, sample for sample. The gate
/// still stands: a label that would look the same is not reassigned.
@MainActor
@Observable
final class StatusItemReadout {
    enum Content: Equatable {
        case icon
        case value(symbol: String, text: String)
        case bars([Bar])
    }

    /// One column of the bar chart, as tall as it can be told apart.
    struct Bar: Equatable {
        let kind: MetricKind
        let level: Int

        /// The glyph is 15 pt tall on a 2x menu bar: 30 rows of pixels, and no
        /// point in redrawing for a change smaller than one of them.
        static let levels = 30

        init(kind: MetricKind, fraction: Double) {
            self.kind = kind
            level = Int((fraction.clamped01 * Double(Self.levels)).rounded())
        }

        var fraction: Double { Double(level) / Double(Self.levels) }
    }

    private(set) var content: Content = .icon

    @ObservationIgnored private let monitor: SystemMonitor
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private lazy var changes = ObservationLoop(self) { readout in
        _ = readout.source
        _ = readout.preferences.menuBarStyle
        _ = readout.preferences.menuBarMetric
        _ = readout.preferences.dashboardMetrics
    } onChange: { readout in
        readout.update()
    }

    /// The snapshot the label is drawn from. Read inside the observation loop,
    /// so switching the setting moves the tracking from one to the other.
    private var source: MetricsSnapshot {
        preferences.isMenuBarRealTime ? monitor.snapshot : monitor.coarseSnapshot
    }

    init(monitor: SystemMonitor, preferences: Preferences) {
        self.monitor = monitor
        self.preferences = preferences
    }

    func start() {
        update()
        changes.start()
    }

    private func update() {
        let fresh = Self.content(for: source, preferences: preferences)
        if fresh != content { content = fresh }
    }

    private static func content(for snapshot: MetricsSnapshot, preferences: Preferences) -> Content {
        switch preferences.menuBarStyle {
        case .graph:
            return .bars(preferences.dashboardMetrics.map { Bar(kind: $0, fraction: snapshot.fraction(for: $0)) })
        case .percentage:
            // A metric stored before the hardware was known — fans on a fanless
            // Mac — would otherwise sit in the menu bar reading n/a for good.
            let metric = snapshot.supports(preferences.menuBarMetric) ? preferences.menuBarMetric : .cpu
            return .value(symbol: metric.symbolName, text: snapshot.headline(for: metric))
        case .icon:
            return .icon
        }
    }
}
