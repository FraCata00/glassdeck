import Foundation
import IOKit

/// Reads GPU utilisation from the `IOAccelerator` registry entries.
///
/// Apple silicon and discrete AMD GPUs both publish a `PerformanceStatistics`
/// dictionary; the keys below are the ones present on every Mac shipped with
/// Metal support. No entitlement or elevated privilege is required.
///
/// A Mac can expose several accelerators — integrated plus discrete, plus a
/// virtual one — so the sampler follows one device rather than re-picking the
/// busiest on every tick, which made the reported name and number jump between
/// GPUs from one sample to the next.
public final class GPUSampler {
    /// One accelerator, paired with the registry entry ID that identifies it
    /// across samples. Internal so the hand-over rule can be tested.
    struct Accelerator: Equatable {
        let id: UInt64
        let usage: GPUUsage
    }

    /// The accelerator currently being reported.
    private var followed: UInt64?

    /// How much busier another accelerator has to be before it takes the reading
    /// over. Without a margin, two GPUs idling within noise of each other would
    /// swap the name and the number on every sample.
    static let handoverMargin = 0.10

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
        let chosen = Self.select(from: Self.accelerators(), following: followed)
        followed = chosen?.id
        return chosen?.usage ?? .zero
    }

    /// Picks the accelerator to report: the one already being followed, unless
    /// another is clearly busier, or the busiest when nothing is followed yet
    /// (first sample) or the followed device has gone away (an eGPU unplugged).
    static func select(from accelerators: [Accelerator], following followed: UInt64?) -> Accelerator? {
        let busiest = accelerators.max { $0.usage.utilisation < $1.usage.utilisation }
        guard let current = accelerators.first(where: { $0.id == followed }) else { return busiest }
        guard let busiest, busiest.usage.utilisation > current.usage.utilisation + handoverMargin else {
            return current
        }
        return busiest
    }

    private static func accelerators() -> [Accelerator] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var found: [Accelerator] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            // The registry entry ID is stable for as long as the device is
            // attached, which is exactly the lifetime we need to track it over.
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS,
                  let usage = usage(of: entry)
            else { continue }
            found.append(Accelerator(id: id, usage: usage))
        }
        return found
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
