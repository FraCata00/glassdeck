import Foundation
import IOKit.ps

/// Charge level and power state, read from the IOKit power-source registry.
///
/// Everything here is public API and needs no privileges; desktops simply report
/// no internal battery, which the UI treats as "not applicable".
public final class BatterySampler {
    public init() {}

    public func sample() -> BatteryUsage {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return .unavailable }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0
            let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 100
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let isPluggedIn = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            // The two time estimates are mutually exclusive and are `-1` while the
            // system is still working the number out.
            let minutes = isCharging
                ? (description[kIOPSTimeToFullChargeKey] as? NSNumber)?.intValue
                : (description[kIOPSTimeToEmptyKey] as? NSNumber)?.intValue

            return BatteryUsage(
                fraction: maximum > 0 ? (current / maximum).clamped01 : 0,
                isCharging: isCharging,
                isPluggedIn: isPluggedIn,
                minutesRemaining: (minutes ?? -1) > 0 ? minutes : nil,
                isAvailable: true
            )
        }
        return .unavailable
    }
}
