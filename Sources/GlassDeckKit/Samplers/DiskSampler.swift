import Foundation
import IOKit

/// Capacity of the boot volume plus read/write throughput derived from the
/// cumulative byte counters of every block storage driver.
public final class DiskSampler {
    /// One driver's cumulative byte counts. Internal so the delta rule can be
    /// tested without attaching a disk.
    struct IOCounters: Equatable {
        var read: UInt64 = 0
        var written: UInt64 = 0
    }

    /// The previous counters, keyed by each driver's registry entry ID.
    private var previousCounters: [UInt64: IOCounters]?
    private var previousSampleTime: Date?
    private var peak = PeakTracker(floor: DiskUsage.minimumReference)
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
                let moved = Self.bytesMoved(from: previous, to: counters)
                usage.readBytesPerSecond = Double(moved.read) / interval
                usage.writeBytesPerSecond = Double(moved.written) / interval
            }
        }
        previousCounters = counters
        previousSampleTime = now
        usage.referenceBytesPerSecond = peak.observe(usage.busiestBytesPerSecond)
        return usage
    }

    /// Sums the per-driver deltas, the way `NetworkSampler` does per interface.
    ///
    /// Subtracting one grand total from the next could not tell a disk going
    /// away from I/O: ejecting an external drive, or detaching a disk image,
    /// took its lifetime bytes out of the sum, and whatever the other disks did
    /// in that tick was swallowed by the drop — reported as nothing, or as the
    /// difference, never as what happened. Per driver, a disk that comes or
    /// goes simply has no delta yet.
    static func bytesMoved(
        from previous: [UInt64: IOCounters],
        to current: [UInt64: IOCounters]
    ) -> IOCounters {
        var moved = IOCounters()
        for (id, counters) in current {
            guard let last = previous[id] else { continue }
            // A driver's counters only grow; one that went backwards was reset,
            // which is not negative I/O, and contributes nothing rather than
            // wrapping into billions of gigabytes.
            moved.read &+= counters.read >= last.read ? counters.read - last.read : 0
            moved.written &+= counters.written >= last.written ? counters.written - last.written : 0
        }
        return moved
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

    private static func readCounters() -> [UInt64: IOCounters] {
        var counters: [UInt64: IOCounters] = [:]
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator
        ) == KERN_SUCCESS else { return counters }
        defer { IOObjectRelease(iterator) }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            // The registry entry ID is unique for as long as the driver is
            // attached and is never reused, so a replugged disk is a new key.
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS,
                  let statistics = IORegistryEntryCreateCFProperty(
                      entry, "Statistics" as CFString, kCFAllocatorDefault, 0
                  )?.takeRetainedValue() as? [String: Any]
            else { continue }

            counters[id] = IOCounters(
                read: (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0,
                written: (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            )
        }
        return counters
    }
}
