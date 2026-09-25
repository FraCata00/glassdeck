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
        arm()
    }

    private func arm() {
        guard let owner else { return }
        withObservationTracking {
            track(owner)
        } onChange: { [weak self] in
            // Called on whichever thread made the change, and before the new
            // value is stored: the work waits for the main actor, by which time
            // the change has landed.
            Task { @MainActor [weak self] in
                guard let self, let owner = self.owner else { return }
                self.onChange(owner)
                self.arm()
            }
        }
    }
}
