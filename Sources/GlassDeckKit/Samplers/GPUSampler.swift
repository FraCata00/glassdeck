import Foundation
import IOKit

/// Reads GPU utilisation from the `IOAccelerator` registry entries.
///
/// Apple silicon and discrete AMD GPUs both publish a `PerformanceStatistics`
/// dictionary; the keys below are the ones present on every Mac shipped with
/// Metal support. No entitlement or elevated privilege is required.
public final class GPUSampler {
    private enum Key {
        static let performanceStatistics = "PerformanceStatistics"
        static let deviceUtilisation = "Device Utilization %"
        static let rendererUtilisation = "Renderer Utilization %"
        static let tilerUtilisation = "Tiler Utilization %"
        static let inUseMemory = "In use system memory"
        static let allocatedMemory = "Alloc system memory"
        static let model = "model"
    }

    public init() {}

    public func sample() -> GPUUsage {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return .zero
        }
        defer { IOObjectRelease(iterator) }

        // Machines can expose several accelerators (integrated + discrete + virtual);
        // the busiest one is the interesting one.
        var best = GPUUsage.zero
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let usage = Self.usage(of: entry) else { continue }
            if !best.isAvailable || usage.utilisation > best.utilisation {
                best = usage
            }
        }
        return best
    }

    private static func usage(of entry: io_registry_entry_t) -> GPUUsage? {
        guard let statistics = IORegistryEntryCreateCFProperty(
            entry, Key.performanceStatistics as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? [String: Any] else { return nil }

        func percentage(_ key: String) -> Double {
            ((statistics[key] as? NSNumber)?.doubleValue ?? 0) / 100
        }

        return GPUUsage(
            name: name(of: entry),
            utilisation: percentage(Key.deviceUtilisation).clamped01,
            rendererUtilisation: percentage(Key.rendererUtilisation).clamped01,
            tilerUtilisation: percentage(Key.tilerUtilisation).clamped01,
            allocatedMemory: (statistics[Key.allocatedMemory] as? NSNumber)?.uint64Value
                ?? (statistics[Key.inUseMemory] as? NSNumber)?.uint64Value ?? 0,
            isAvailable: true
        )
    }

    /// The `model` property is a NUL-terminated C string stored as data on Apple
    /// silicon and a plain string on some Intel Macs, so both shapes are handled.
    private static func name(of entry: io_registry_entry_t) -> String {
        guard let model = IORegistryEntrySearchCFProperty(
            entry, kIOServicePlane, Key.model as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        ) else { return "GPU" }

        if let string = model as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let data = model as? Data {
            let bytes = data.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        return "GPU"
    }
}
