import Foundation
import Observation

/// Publishes the time, once a minute, on the minute.
///
/// The clock module cannot ride on the sampler: the sampler runs every second
/// and a half, and every surface that reads it redraws when it fires — the
/// status item most expensively of all. A clock that shows minutes needs 40
/// times fewer wake-ups than that, and needs them at the moment the minute
/// turns rather than a random fraction of a second later, or the menu bar sits
/// on the wrong minute for up to a second and a half.
///
/// Nothing reads seconds anywhere, which is what makes one wake-up a minute
/// enough.
@MainActor
@Observable
final class ClockTicker {
    /// The instant the surfaces format. Reassigned on every minute boundary,
    /// which is what invalidates the views reading it.
    private(set) var now: Date = Date()

    @ObservationIgnored private var task: Task<Void, Never>?

    /// Runs only while something is showing a clock. Nothing does by default, so
    /// an app whose owner never adds a time zone never schedules a thing.
    @ObservationIgnored private(set) var isEnabled = false

    /// Whether the settings say a clock is on screen somewhere.
    @ObservationIgnored private var isWanted = false

    /// How many views are showing a time of their own right now — the settings
    /// tab previews one beside every zone, and those have to tick even before
    /// the module has been switched on.
    @ObservationIgnored private var holds = 0

    func setWanted(_ wanted: Bool) {
        isWanted = wanted
        apply()
    }

    /// Keeps the ticker running for as long as a view needs it. Balance every
    /// call with `endObserving()`.
    func beginObserving() {
        holds += 1
        apply()
    }

    func endObserving() {
        holds = max(0, holds - 1)
        apply()
    }

    private func apply() {
        let enabled = isWanted || holds > 0
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            refresh()
            start()
        } else {
            task?.cancel()
            task = nil
        }
    }

    /// Catches the clock up out of band — after a wake, where the sleep below
    /// has been asleep along with the machine.
    func refresh() {
        now = Date()
    }

    private func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(Self.secondsToNextMinute(from: Date())))
                guard !Task.isCancelled else { return }
                self.now = Date()
            }
        }
    }

    /// A hair past the boundary rather than exactly on it, so the formatter is
    /// never handed 10:59:59.998 and asked to write 11:00.
    static func secondsToNextMinute(from date: Date) -> Double {
        60 - date.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) + 0.05
    }
}
