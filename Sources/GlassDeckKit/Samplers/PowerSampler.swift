import Foundation

/// Reads how much power the machine is drawing right now.
///
/// The reading is reused for a couple of seconds, the same bargain the
/// thermometers and the fans make: the adapter rating never moves, and the
/// wattage is a rolling average inside the SMC rather than an instant, so a
/// round trip per tick was paying for precision the sensor does not have.
public final class PowerSampler {
    /// How long a reading stands before the SMC is asked again.
    ///
    /// Kept to the shortest useful cache — the same two seconds the menu bar is
    /// throttled to — because power is the spikiest of the SMC metrics and its
    /// sparkline is the one that would show a longer hold as a staircase. At the
    /// default 1.5 s cadence a reading is taken every other tick, every three
    /// seconds; asking on every tick would be a per-tick SMC read.
    static let refreshInterval: TimeInterval = 2

    private let smc: SMCService?
    private let catalogue: SensorCatalogue
    private var cache: ReadingCache<PowerUsage>

    /// How many times the sensors have actually been read. Internal, so a test
    /// can tell a reused reading from a fresh one without any hardware.
    private(set) var readCount = 0

    init(smc: SMCService?, catalogue: SensorCatalogue, refreshInterval: TimeInterval = PowerSampler.refreshInterval) {
        self.smc = smc
        self.catalogue = catalogue
        self.cache = ReadingCache(interval: refreshInterval)
    }

    public func sample(at now: Date = Date()) -> PowerUsage {
        cache.value(at: now) { read() }
    }

    private func read() -> PowerUsage {
        readCount += 1
        guard let smc, let key = catalogue.systemPower, let watts = smc.readNumber(key), watts > 0 else {
            return .unavailable
        }

        return PowerUsage(
            watts: watts,
            // The adapter's rating makes a far better full-scale mark than an
            // arbitrary constant: on a 65 W charger, 65 W really is "everything".
            adapterWatts: catalogue.adapterPower.flatMap { smc.readNumber($0) },
            isAvailable: true
        )
    }
}
