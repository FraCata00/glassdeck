import Foundation

/// Compact, allocation-light formatters shared by the window UI and the Touch Bar.
public enum ValueFormatter {
    /// `0.4213` → `"42%"`.
    public static func percent(_ fraction: Double) -> String {
        "\(Int((fraction.clamped01 * 100).rounded()))%"
    }

    /// Byte counts in binary units with adaptive precision: `"9.1 GB"`, `"512 MB"`.
    public static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var amount = Double(value)
        var index = 0
        while amount >= 1024, index < units.count - 1 {
            amount /= 1024
            index += 1
        }
        if index == 0 { return "\(value) B" }
        return amount < 10
            ? String(format: "%.1f %@", amount, units[index])
            : String(format: "%.0f %@", amount, units[index])
    }

    /// Throughput with a `/s` suffix: `"1.4 MB/s"`.
    public static func rate(_ bytesPerSecond: Double) -> String {
        let value = bytesPerSecond.isFinite && bytesPerSecond > 0 ? UInt64(bytesPerSecond) : 0
        return "\(bytes(value))/s"
    }

    /// One decimal place, used for load averages.
    public static func decimal(_ value: Double) -> String {
        String(format: "%.2f", value.isFinite ? value : 0)
    }
}
