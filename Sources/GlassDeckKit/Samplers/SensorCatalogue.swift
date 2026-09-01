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

    /// The channel suffixes an Apple silicon thermometer is published under, in
    /// the order they are preferred.
    ///
    /// A sensor appears four times — `Tp9a`, `Tp9b`, `Tp9x`, `Tp9z` — and the
    /// four are not four places on the die: they track one signal, offset from
    /// each other by an amount that reaches 17 °C and holds steady through a
    /// load ramp and the cooldown after it. Keeping all four and taking the
    /// hottest therefore reported the highest-offset channel and nothing else.
    ///
    /// `b` is the one kept, because it is the channel whose absolute value stays
    /// coherent with the rest of the machine: measured on an M1 at rest, `Tp9b`
    /// read 51.0 °C beside an enclosure at 39 °C and a battery at 37 °C, where
    /// `Tp9z` claimed 66.7 °C and put that same idle enclosure at 46 °C. Under
    /// load `TCMz` reached 100.8 °C against 87.2 °C on `TCMb` — enough to fire
    /// the temperature alert on a Mac that was not throttling.
    private static let channelPreference: [Character] = ["b", "a", "x", "z"]

    var cpu: [String] = []
    var gpu: [String] = []
    var battery: [String] = []
    var enclosure: [String] = []
    var systemPower: String?
    var adapterPower: String?

    var hasTemperatures: Bool { !(cpu.isEmpty && gpu.isEmpty && battery.isEmpty && enclosure.isEmpty) }

    init(smc: SMCService?) {
        guard let smc else { return }

        let thermometers = smc.allKeys().filter { key in
            guard key.hasPrefix("T") else { return false }
            guard let value = smc.readNumber(key) else { return false }
            return Self.plausibleTemperature.contains(value)
        }

        for key in Self.oneChannelPerSensor(thermometers) {
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

    /// Reduces the redundant channels of one sensor to the preferred one, so a
    /// sensor is counted once rather than four times.
    ///
    /// Keys that do not end in a channel suffix are left exactly as they are:
    /// this scheme is what Apple silicon publishes, and an Intel Mac — whose
    /// keys end in `P`, `D`, `E` or `F` — must keep every one of them.
    static func oneChannelPerSensor(_ keys: [String]) -> [String] {
        var preferred: [String: String] = [:]
        var unchannelled: [String] = []

        for key in keys {
            guard key.count == 4, let channel = key.last,
                  let rank = channelPreference.firstIndex(of: channel)
            else {
                unchannelled.append(key)
                continue
            }

            let sensor = String(key.dropLast())
            let incumbent = preferred[sensor]?.last
                .flatMap(channelPreference.firstIndex(of:)) ?? channelPreference.count
            if rank < incumbent { preferred[sensor] = key }
        }

        return (unchannelled + preferred.values).sorted()
    }
}
