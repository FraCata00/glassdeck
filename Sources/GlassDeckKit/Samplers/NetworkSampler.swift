import Darwin
import Foundation

/// Aggregate interface throughput derived from the `if_data` byte counters.
///
/// Loopback and inactive interfaces are skipped so the numbers match what the
/// user actually sends over the wire or the air.
public final class NetworkSampler {
    private struct Counters {
        var received: UInt64 = 0
        var sent: UInt64 = 0
    }

    private var previous: Counters?
    private var previousSampleTime: Date?

    public init() {}

    public func sample(at now: Date = Date()) -> NetworkThroughput {
        let counters = Self.readCounters()
        defer {
            previous = counters
            previousSampleTime = now
        }

        guard let previous, let previousTime = previousSampleTime else { return .zero }
        let interval = now.timeIntervalSince(previousTime)
        guard interval > 0 else { return .zero }

        return NetworkThroughput(
            downloadBytesPerSecond: Double(counters.received &- previous.received) / interval,
            uploadBytesPerSecond: Double(counters.sent &- previous.sent) / interval
        )
    }

    private static func readCounters() -> Counters {
        var counters = Counters()
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return counters }
        defer { freeifaddrs(addresses) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: interface.ifa_name)
            guard !name.hasPrefix("lo"), !name.hasPrefix("gif"), !name.hasPrefix("stf") else { continue }
            guard let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }

            counters.received &+= UInt64(data.pointee.ifi_ibytes)
            counters.sent &+= UInt64(data.pointee.ifi_obytes)
        }
        return counters
    }
}
