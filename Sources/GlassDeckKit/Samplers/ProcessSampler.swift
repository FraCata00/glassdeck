import Darwin
import Foundation

/// Ranks running processes by CPU time consumed between two samples.
///
/// Everything comes from `libproc`, so there is no `ps` subprocess to spawn.
/// Processes owned by other users are skipped silently: `proc_pidinfo` refuses
/// them without elevated privileges, and GlassDeck deliberately stays unprivileged.
public final class ProcessSampler {
    private struct CPUTime {
        var nanoseconds: UInt64
        var timestamp: Date
    }

    private var previous: [Int32: CPUTime] = [:]
    private let activeProcessorCount = Double(ProcessInfo.processInfo.activeProcessorCount)

    public init() {}

    /// - Parameter limit: how many top consumers to return.
    public func sample(limit: Int = 5, at now: Date = Date()) -> [ProcessSample] {
        let pids = Self.runningPIDs()
        var current: [Int32: CPUTime] = [:]
        current.reserveCapacity(pids.count)
        var samples: [ProcessSample] = []

        for pid in pids where pid > 0 {
            var info = proc_taskinfo()
            let size = MemoryLayout<proc_taskinfo>.size
            let read = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(size))
            guard read == Int32(size) else { continue }

            let cpuTime = CPUTime(nanoseconds: info.pti_total_user &+ info.pti_total_system, timestamp: now)
            current[pid] = cpuTime

            guard let last = previous[pid] else { continue }
            let interval = now.timeIntervalSince(last.timestamp)
            guard interval > 0, cpuTime.nanoseconds >= last.nanoseconds else { continue }

            let seconds = Double(cpuTime.nanoseconds - last.nanoseconds) / 1_000_000_000
            let percent = (seconds / interval) * 100
            guard percent >= 0.1 else { continue }

            samples.append(
                ProcessSample(
                    id: pid,
                    name: Self.name(of: pid),
                    cpuPercent: percent,
                    memoryBytes: info.pti_resident_size
                )
            )
        }

        previous = current
        return Array(samples.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit))
    }

    private static func runningPIDs() -> [Int32] {
        let capacity = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard capacity > 0 else { return [] }
        let count = Int(capacity) / MemoryLayout<Int32>.size
        var pids = [Int32](repeating: 0, count: count)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, capacity)
        guard written > 0 else { return [] }
        return Array(pids.prefix(Int(written) / MemoryLayout<Int32>.size))
    }

    private static func name(of pid: Int32) -> String {
        var buffer = [UInt8](repeating: 0, count: Int(2 * MAXCOMLEN) + 1)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "pid \(pid)" }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
}
