import Foundation

/// Compact, allocation-light formatters shared by the window UI and the Touch Bar.
public enum ValueFormatter {
    /// `0.4213` → `"42%"`.
    public static func percent(_ fraction: Double) -> String {
        "\(Int((fraction.clamped01 * 100).rounded()))%"
    }

    /// Memory in binary units with adaptive precision: `"9.1 GB"`, `"512 MB"`.
    ///
    /// Binary because that is how macOS counts memory — Activity Monitor calls
    /// 8 GiB of RAM "8 GB" — and the number has to match the one it shows.
    public static func bytes(_ value: UInt64) -> String {
        scaled(value, base: 1024)
    }

    /// Storage capacity in decimal units: `"494 GB"`.
    ///
    /// Decimal because that is how Finder, System Settings and the drive's
    /// own box count it. In binary units a 494 GB volume read as 460 GB, and
    /// the free space disagreed with Finder by the same seven per cent.
    public static func storage(_ value: UInt64) -> String {
        scaled(value, base: 1000)
    }

    /// Throughput with a `/s` suffix, in decimal units: `"1.4 MB/s"` — what
    /// Activity Monitor's Disk and Network tabs show.
    ///
    /// Converting a `Double` at or above `UInt64.max` is a hard trap, not a
    /// rounding error, so the value saturates instead: a rate that large can only
    /// be a bad reading, and a wrong label beats a crashed menu bar.
    public static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "\(storage(0))/s" }
        let value = bytesPerSecond >= Double(UInt64.max) ? UInt64.max : UInt64(bytesPerSecond)
        return "\(storage(value))/s"
    }

    private static func scaled(_ value: UInt64, base: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var amount = Double(value)
        var index = 0
        // Promoted on the figure as it will be printed, not as it is: 1023.7 MB
        // only reaches 1024 when rounded, and a test on the raw amount let it
        // through as "1024 MB" where the next unit reads "1.0 GB".
        while index < units.count - 1, amount.rounded() >= base {
            amount /= base
            index += 1
        }
        if index == 0 { return "\(value) B" }
        // Rounded first, so 9.96 becomes "10" rather than "10.0".
        let rounded = (amount * 10).rounded() / 10
        // The whole figure is rounded here too rather than left to `%.0f`,
        // which rounds a half to even: 10.5 GB printed as "10" while 11.5
        // printed as "12".
        return rounded < 10
            ? String(format: "%.1f %@", rounded, units[index])
            : String(format: "%.0f %@", amount.rounded(), units[index])
    }

    /// Two decimal places, matching how `uptime` prints load averages.
    public static func decimal(_ value: Double) -> String {
        String(format: "%.2f", value.isFinite ? value : 0)
    }

    /// Minutes as hours and minutes: `125` → `"2h 5m"`, `45` → `"45m"`.
    public static func duration(minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// A temperature to the nearest degree: `54.4` → `"54°C"`.
    public static func celsius(_ degrees: Double) -> String {
        "\(degrees.roundedInt)°C"
    }

    /// One decimal place, for a cadence the user picked on a slider: the
    /// half-second steps read as `1.5`, not as `1.50`.
    public static func seconds(_ value: Double) -> String {
        String(format: "%.1f", value.isFinite ? value : 0)
    }
}
