import Foundation

/// Reads fan speeds from the SMC.
///
/// The fan count and each fan's rated range are static, so they are read once;
/// only the live RPM is polled on every sample.
///
/// Like the thermometers, the RPM is then reused for a few seconds rather than
/// re-read on every tick. A fan controller moves the blades over seconds, not
/// milliseconds, so the extra SMC round trips bought a number that had not
/// changed.
public final class FanSampler {
    /// How long a reading stands before the SMC is asked again.
    ///
    /// Three seconds outlives two ticks at the default cadence and still lands
    /// well inside the time a fan takes to visibly change speed.
    static let refreshInterval: TimeInterval = 3

    private let smc: SMCService?
    private let descriptors: [(index: Int, minimum: Double, maximum: Double)]
    private let interval: TimeInterval

    private var cached: FanUsage?
    private var cachedAt: Date?

    /// How many times the fans have actually been read. Internal, so a test can
    /// tell a reused reading from a fresh one without any hardware.
    private(set) var readCount = 0

    init(smc: SMCService?, refreshInterval: TimeInterval = FanSampler.refreshInterval) {
        self.smc = smc
        self.interval = refreshInterval

        guard let smc, let count = smc.readNumber("FNum"), count > 0 else {
            descriptors = []
            return
        }

        descriptors = (0..<Int(count)).map { index in
            (
                index: index,
                minimum: smc.readNumber("F\(index)Mn") ?? 0,
                maximum: smc.readNumber("F\(index)Mx") ?? 6000
            )
        }
    }

    public func sample(at now: Date = Date()) -> FanUsage {
        if let cached, let cachedAt, now.timeIntervalSince(cachedAt) < interval {
            return cached
        }

        let usage = read()
        cached = usage
        cachedAt = now
        return usage
    }

    private func read() -> FanUsage {
        readCount += 1
        guard let smc, !descriptors.isEmpty else { return .unavailable }

        let fans = descriptors.map { descriptor in
            Fan(
                index: descriptor.index,
                rpm: smc.readNumber("F\(descriptor.index)Ac") ?? 0,
                minimumRPM: descriptor.minimum,
                maximumRPM: descriptor.maximum
            )
        }
        return FanUsage(fans: fans, isAvailable: true)
    }
}
