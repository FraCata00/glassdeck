import Darwin
import Foundation

/// Aggregate interface throughput derived from the `if_data` byte counters.
///
/// The kernel's byte counters are **32-bit** and wrap every 4 GiB — minutes of
/// Wi-Fi — so the deltas are taken per interface with `&-`, exactly as
/// `CPUSampler` does for its tick counters: a wrap then cancels itself out and
/// the delta stays correct. Summing the counters first and subtracting after
/// would not survive it, because a sum does not wrap at the same boundary.
///
/// (`NET_RT_IFLIST2` looks like the way out, but the `if_data64` it hands back
/// carries the same truncated 32-bit byte counts on current macOS.)
///
/// Loopback and tunnel interfaces are skipped: a tunnel carries the same bytes
/// a second time on their way to the physical interface, so counting it would
/// double every VPN'd byte.
public final class NetworkSampler {
    /// Internal so the wrap arithmetic can be tested without a network card.
    struct Counters: Equatable {
        var received: UInt32 = 0
        var sent: UInt32 = 0
    }

    private var previous: [String: Counters] = [:]
    private var previousSampleTime: Date?
    private var peak = PeakTracker(floor: NetworkThroughput.minimumReference)

    public init() {}

    public func sample(at now: Date = Date()) -> NetworkThroughput {
        let counters = Self.readCounters()
        defer {
            previous = counters
            previousSampleTime = now
        }

        guard let previousTime = previousSampleTime else { return .zero }
        let interval = now.timeIntervalSince(previousTime)
        guard interval > 0 else { return .zero }

        let moved = Self.bytesMoved(from: previous, to: counters)
        let download = Double(moved.received) / interval
        let upload = Double(moved.sent) / interval

        return NetworkThroughput(
            downloadBytesPerSecond: download,
            uploadBytesPerSecond: upload,
            referenceBytesPerSecond: peak.observe(max(download, upload))
        )
    }

    /// Sums the per-interface deltas. `&-` on the 32-bit counters is what makes a
    /// wrap come out as the handful of bytes it really was.
    static func bytesMoved(
        from previous: [String: Counters],
        to current: [String: Counters]
    ) -> (received: UInt64, sent: UInt64) {
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for (name, counters) in current {
            // An interface that was not in the previous sample — a VPN that just
            // came up, a dongle just plugged in — has no delta to contribute yet.
            guard let last = previous[name] else { continue }
            received &+= UInt64(counters.received &- last.received)
            sent &+= UInt64(counters.sent &- last.sent)
        }
        return (received, sent)
    }

    private static func readCounters() -> [String: Counters] {
        var counters: [String: Counters] = [:]
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return counters }
        defer { freeifaddrs(addresses) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: interface.ifa_name)
            guard Self.isCounted(name) else { continue }
            guard let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }

            counters[name] = Counters(
                received: data.pointee.ifi_ibytes,
                sent: data.pointee.ifi_obytes
            )
        }
        return counters
    }

    /// `utun`/`ipsec` are the tunnels whose traffic is already counted on the
    /// interface underneath them.
    private static func isCounted(_ name: String) -> Bool {
        let excluded = ["lo", "gif", "stf", "utun", "ipsec"]
        return !name.isEmpty && !excluded.contains { name.hasPrefix($0) }
    }
}
