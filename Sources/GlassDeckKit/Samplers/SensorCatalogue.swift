import Foundation

/// The SMC sensor keys this particular Mac actually has.
///
/// Key names are model specific, so the catalogue is built once by enumerating
/// the SMC and keeping the keys that return a plausible reading. Sampling then
/// touches only those, which costs well under a millisecond.
struct SensorCatalogue {
    /// Plausible range for a temperature sensor in degrees Celsius. Anything
    /// outside it is a key that happens to start with `T` but is not a thermometer.
    static let plausibleTemperature: ClosedRange<Double> = 5...120

    var cpu: [String] = []
    var gpu: [String] = []
    var battery: [String] = []
    var enclosure: [String] = []
    var systemPower: String?
    var adapterPower: String?

    var hasTemperatures: Bool { !(cpu.isEmpty && gpu.isEmpty && battery.isEmpty && enclosure.isEmpty) }

    init(smc: SMCService?) {
        guard let smc else { return }

        for key in smc.allKeys() {
            guard key.hasPrefix("T") else { continue }
            guard let value = smc.readNumber(key), Self.plausibleTemperature.contains(value) else { continue }

            switch true {
            // Apple silicon publishes per-cluster die sensors (`Tp*`); Intel Macs
            // publish CPU proximity as `TC*`.
            case key.hasPrefix("Tp"), key.hasPrefix("TC"), key.hasPrefix("Tc"):
                cpu.append(key)
            case key.hasPrefix("Tg"), key.hasPrefix("TG"):
                gpu.append(key)
            case key.hasPrefix("TB"):
                battery.append(key)
            case key.hasPrefix("Ts"), key.hasPrefix("Th"):
                enclosure.append(key)
            default:
                break
            }
        }

        // `PSTR` is the system total on both architectures; the others are the
        // rails that stand in for it on models that do not publish it.
        systemPower = ["PSTR", "PMVR", "PPBR", "PDTR"].first { (smc.readNumber($0) ?? 0) > 0 }
        adapterPower = ["PHPB", "PZl0"].first { (smc.readNumber($0) ?? 0) > 0 }
    }
}
