import Foundation

/// Reads the machine's thermometers through the SMC.
///
/// This is by far the most expensive sampler: a Mac publishes dozens of
/// thermometers — 83 on the machine this was measured on — and each one is its
/// own round trip to the SMC, which added up to about 20 ms per sample against
/// well under 1 ms for every other metric combined.
///
/// Temperature moves with the machine's thermal mass rather than with the
/// sampling cadence, so a reading is reused for a few seconds instead of being
/// taken afresh on every tick. Nothing else is traded away: when the sensors are
/// read, all of them still are, and the hottest still wins.
public final class ThermalSampler {
    /// How long a reading stands before the sensors are read again.
    ///
    /// Five seconds cuts the cost of a sample from about 19 ms to 4.7 ms at the
    /// default cadence. Longer would save more — ten seconds reaches 2.3 ms —
    /// but the history keeps 60 samples, and at that point the temperature
    /// sparkline is a staircase of nine steps rather than a curve.
    static let refreshInterval: TimeInterval = 5

    private let smc: SMCService?
    private let catalogue: SensorCatalogue

    private var cached: ThermalUsage?
    private var cachedAt: Date?

    /// How many times the sensors have actually been read. Internal, so a test
    /// can tell a reused reading from a fresh one without any hardware.
    private(set) var readCount = 0

    private let interval: TimeInterval

    init(smc: SMCService?, catalogue: SensorCatalogue, refreshInterval: TimeInterval = ThermalSampler.refreshInterval) {
        self.smc = smc
        self.catalogue = catalogue
        self.interval = refreshInterval
    }

    public func sample(at now: Date = Date()) -> ThermalUsage {
        if let cached, let cachedAt, now.timeIntervalSince(cachedAt) < interval {
            return cached
        }

        let usage = read()
        cached = usage
        cachedAt = now
        return usage
    }

    private func read() -> ThermalUsage {
        readCount += 1
        guard let smc, catalogue.hasTemperatures else { return .unavailable }

        return ThermalUsage(
            cpu: hottest(of: catalogue.cpu, using: smc),
            gpu: hottest(of: catalogue.gpu, using: smc),
            battery: hottest(of: catalogue.battery, using: smc),
            enclosure: hottest(of: catalogue.enclosure, using: smc),
            sensorCount: catalogue.cpu.count + catalogue.gpu.count
                + catalogue.battery.count + catalogue.enclosure.count,
            isAvailable: true
        )
    }

    /// The hottest sensor in a group is the one that matters: it is what the fans
    /// and the throttler react to.
    private func hottest(of keys: [String], using smc: SMCService) -> Double? {
        keys
            .compactMap { smc.readNumber($0) }
            .filter { SensorCatalogue.plausibleTemperature.contains($0) }
            .max()
    }
}
