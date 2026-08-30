import Foundation
import IOKit

/// Capacity of the boot volume plus read/write throughput derived from the
/// cumulative byte counters of every block storage driver.
public final class DiskSampler {
    private struct IOCounters {
        var read: UInt64 = 0
        var written: UInt64 = 0
    }

    private var previousCounters: IOCounters?
    private var previousSampleTime: Date?
    private let volumeURL: URL

    public init(volumeURL: URL = URL(fileURLWithPath: "/")) {
        self.volumeURL = volumeURL
    }

    public func sample(at now: Date = Date()) -> DiskUsage {
        var usage = capacity()

        let counters = Self.readCounters()
        if let previous = previousCounters, let previousTime = previousSampleTime {
            let interval = now.timeIntervalSince(previousTime)
            if interval > 0 {
                usage.readBytesPerSecond = Double(counters.read &- previous.read) / interval
                usage.writeBytesPerSecond = Double(counters.written &- previous.written) / interval
            }
        }
        previousCounters = counters
        previousSampleTime = now
        return usage
    }

    private func capacity() -> DiskUsage {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeNameKey,
        ]
        guard let values = try? volumeURL.resourceValues(forKeys: keys) else { return .zero }

        // `importantUsage` matches the number Finder shows: it counts purgeable space.
        let free = values.volumeAvailableCapacityForImportantUsage.map(UInt64.init)
            ?? values.volumeAvailableCapacity.map { UInt64($0) } ?? 0

        return DiskUsage(
            volumeName: values.volumeName ?? "Macintosh HD",
            total: UInt64(values.volumeTotalCapacity ?? 0),
            free: free
        )
    }

    private static func readCounters() -> IOCounters {
        var counters = IOCounters()
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator
        ) == KERN_SUCCESS else { return counters }
        defer { IOObjectRelease(iterator) }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let statistics = IORegistryEntryCreateCFProperty(
                entry, "Statistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] else { continue }

            counters.read &+= (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            counters.written &+= (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return counters
    }
}
