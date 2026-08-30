import Foundation

/// Remembers the fastest rate a sampler has seen, so a throughput gauge can be
/// scaled against what this machine actually does rather than against a constant.
///
/// A fixed full scale cannot suit both a 10 Mbit connection and a 10 Gbit one:
/// the network gauge used a 100 Mbit reference, so on a fast link any real
/// download pinned it to full and it stopped saying anything.
///
/// The peak decays a little on every sample, so one burst does not flatten the
/// gauge for the rest of the session — at the default cadence a peak fades by
/// half in about a minute — and it never falls below a floor, so idle noise does
/// not amplify into a full meter.
struct PeakTracker {
    private let floor: Double
    private let decay: Double
    private(set) var peak: Double

    init(floor: Double, decay: Double = 0.98) {
        self.floor = floor
        self.decay = decay
        self.peak = floor
    }

    /// Folds a new reading in and returns the scale to measure it against.
    @discardableResult
    mutating func observe(_ value: Double) -> Double {
        guard value.isFinite, value >= 0 else { return peak }
        peak = Swift.max(floor, Swift.max(value, peak * decay))
        return peak
    }
}
