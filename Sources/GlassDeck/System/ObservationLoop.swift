import Observation

/// Watches `@Observable` state from outside SwiftUI.
///
/// `withObservationTracking` fires once, for the first change to anything read
/// in its closure, and then has to be armed again: this does the re-arming, so
/// `onChange` runs after every change for as long as the owner lives. The
/// properties are read afresh on each arming, so a `track` that chooses what
/// to read from the owner's own state follows that state as it moves.
///
/// The owner is held weakly — it is the object that keeps the loop — and the
/// loop retires once it is gone.
@MainActor
final class ObservationLoop<Owner: AnyObject> {
    private weak var owner: Owner?
    private let track: @MainActor (Owner) -> Void
    private let onChange: @MainActor (Owner) -> Void
    private var isRunning = false
    /// Bumped on every start and stop. A tracking closure that was armed under
    /// an older generation cannot be withdrawn — `withObservationTracking` has
    /// no cancellation — so when it fires it is simply ignored, and a stop
    /// followed by a start never leaves two chains re-arming side by side.
    private var generation = 0

    /// - Parameters:
    ///   - track: Reads the properties to watch.
    ///   - onChange: Runs on the main actor after any of them has changed.
    init(
        _ owner: Owner,
        track: @escaping @MainActor (Owner) -> Void,
        onChange: @escaping @MainActor (Owner) -> Void
    ) {
        self.owner = owner
        self.track = track
        self.onChange = onChange
    }

    /// Starts watching. Calling it again does nothing.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        generation += 1
        arm(generation)
    }

    /// Stops watching: `onChange` does not run again until the next `start()`.
    /// For an owner whose surface can go away while the owner lives on, such
    /// as the Touch Bar switched off in settings.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation += 1
    }

    private func arm(_ armedGeneration: Int) {
        guard let owner else { return }
        withObservationTracking {
            track(owner)
        } onChange: { [weak self] in
            // Called on whichever thread made the change, and before the new
            // value is stored: the work waits for the main actor, by which time
            // the change has landed.
            Task { @MainActor [weak self] in
                guard let self, self.generation == armedGeneration, let owner = self.owner else { return }
                self.onChange(owner)
                self.arm(armedGeneration)
            }
        }
    }
}
