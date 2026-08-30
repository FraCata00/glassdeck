import Foundation

/// Reads the machine's thermometers through the SMC.
public final class ThermalSampler {
    private let smc: SMCService?
    private let catalogue: SensorCatalogue

    init(smc: SMCService?, catalogue: SensorCatalogue) {
        self.smc = smc
        self.catalogue = catalogue
    }

    public func sample() -> ThermalUsage {
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
