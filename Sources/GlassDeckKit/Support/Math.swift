import Foundation

extension Double {
    /// Clamps the value into the unit interval.
    ///
    /// NaN becomes `0` — a missing reading should show as empty, not as full —
    /// while infinities clamp to the end of the range they point at.
    public var clamped01: Double {
        if isNaN { return 0 }
        return Swift.min(1, Swift.max(0, self))
    }

    /// Moves the value a fraction of the way towards `target`; used to damp gauge jitter.
    public func smoothed(towards target: Double, factor: Double) -> Double {
        let f = factor.clamped01
        return self + (target - self) * f
    }
}

extension Collection where Element == Double {
    /// Arithmetic mean, or `0` for an empty collection.
    public var mean: Double {
        isEmpty ? 0 : reduce(0, +) / Double(count)
    }
}
