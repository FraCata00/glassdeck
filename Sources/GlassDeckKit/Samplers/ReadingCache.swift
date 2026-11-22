import Foundation

/// A reading that stands for a fixed time before its source is asked again.
///
/// The SMC samplers and the Bluetooth sampler all make the same bargain — a
/// round trip is dear and the value moves slowly — and each used to keep its
/// own copy of the arithmetic. It lives here once, so the one subtle case is
/// handled once.
struct ReadingCache<Value> {
    let interval: TimeInterval

    private var value: Value?
    private var takenAt: Date?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    /// The kept reading while it is still fresh at `now`; otherwise a new one
    /// from `read`, which is then kept in its place.
    ///
    /// The timestamps are wall-clock `Date`s, and the wall clock can step
    /// backwards — a manual change, or a network time correction after a long
    /// sleep. A reading from the "future" is treated as stale: taken as fresh,
    /// its negative age stayed under the interval until the clock caught up
    /// again, which froze the temperatures, the fans and the wattage for as
    /// long as the clock had gone back.
    mutating func value(at now: Date, reading read: () -> Value) -> Value {
        if let value, let takenAt {
            let age = now.timeIntervalSince(takenAt)
            if age >= 0, age < interval { return value }
        }
        let fresh = read()
        value = fresh
        takenAt = now
        return fresh
    }
}
