import Foundation

/// Reads how much power the machine is drawing right now.
public final class PowerSampler {
    private let smc: SMCService?
    private let catalogue: SensorCatalogue

    init(smc: SMCService?, catalogue: SensorCatalogue) {
        self.smc = smc
        self.catalogue = catalogue
    }

    public func sample() -> PowerUsage {
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
