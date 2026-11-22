import Darwin
import Foundation

/// Ranks running processes by CPU time consumed between two samples.
///
/// Everything comes from `libproc`, so there is no `ps` subprocess to spawn.
/// Processes owned by other users are skipped silently: `proc_pidinfo` refuses
/// them without elevated privileges, and GlassDeck deliberately stays unprivileged.
public final class ProcessSampler {
    private struct CPUTime {
        var ticks: UInt64
        var timestamp: Date
    }

    private var previous: [Int32: CPUTime] = [:]

    /// Nanoseconds per Mach absolute-time tick, as `numer / denom`. Internal,
    /// so a test can check the conversion against the process's own CPU clock.
    ///
    /// `pti_total_user` and `pti_total_system` are in Mach ticks, not the
    /// nanoseconds they are usually taken for. On Intel a tick is a nanosecond,
    /// so the two never differed; on Apple silicon a tick is 125/3 ns, and
    /// reading it as one put every process at 1/41.7 of its real load — a
    /// saturated core read 2.4 % — and dropped most of the list under the
    /// 0.1 % floor. Measured on Apple silicon: a busy loop that
    /// `CLOCK_PROCESS_CPUTIME_ID` timed at 299.8 ms moved the counters by
    /// 7 195 286.
    let timebase: (numer: UInt32, denom: UInt32)

    public init() {
        var info = mach_timebase_info_data_t()
        timebase = mach_timebase_info(&info) == KERN_SUCCESS && info.denom != 0
            ? (info.numer, info.denom)
            : (1, 1)
    }

    /// Converts a span of Mach ticks to seconds. Done in `Double`, so scaling
    /// by the numerator cannot overflow the way `UInt64` arithmetic could.
    static func seconds(ofTicks ticks: UInt64, timebase: (numer: UInt32, denom: UInt32)) -> Double {
        Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }

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

            let cpuTime = CPUTime(ticks: info.pti_total_user &+ info.pti_total_system, timestamp: now)
            current[pid] = cpuTime

            guard let last = previous[pid] else { continue }
            let interval = now.timeIntervalSince(last.timestamp)
            guard interval > 0, cpuTime.ticks >= last.ticks else { continue }

            let seconds = Self.seconds(ofTicks: cpuTime.ticks - last.ticks, timebase: timebase)
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
