import Darwin
import Foundation

/// Reads per-core processor load from the Mach host and turns consecutive tick
/// counters into usage fractions.
///
/// The kernel exposes monotonically increasing tick counters, so a single reading
/// is meaningless: the first `sample()` primes the baseline and returns zeroes.
public final class CPUSampler {
    private var previousTicks: [UInt32] = []
    private let statesPerCore = Int(CPU_STATE_MAX)

    /// Logical cores in the performance cluster (`0` when the machine has no clusters).
    public let performanceCoreCount: Int
    /// Logical cores in the efficiency cluster.
    public let efficiencyCoreCount: Int

    public init() {
        performanceCoreCount = Self.sysctlInt("hw.perflevel0.logicalcpu") ?? 0
        efficiencyCoreCount = Self.sysctlInt("hw.perflevel1.logicalcpu") ?? 0
    }

    public func sample() -> CPUUsage {
        guard let ticks = Self.readTicks() else { return .zero }
        defer { previousTicks = ticks }

        guard previousTicks.count == ticks.count, !previousTicks.isEmpty else {
            return CPUUsage(
                perCore: Array(repeating: 0, count: ticks.count / statesPerCore),
                performanceCoreCount: performanceCoreCount,
                efficiencyCoreCount: efficiencyCoreCount,
                loadAverage: Self.loadAverage()
            )
        }

        let coreCount = ticks.count / statesPerCore
        var perCore: [Double] = []
        perCore.reserveCapacity(coreCount)
        var totals = (user: 0.0, system: 0.0, nice: 0.0, idle: 0.0)

        for core in 0..<coreCount {
            let base = core * statesPerCore
            // Tick counters wrap around at UInt32; `&-` keeps the delta correct when they do.
            let user = Double(ticks[base + Int(CPU_STATE_USER)] &- previousTicks[base + Int(CPU_STATE_USER)])
            let system = Double(ticks[base + Int(CPU_STATE_SYSTEM)] &- previousTicks[base + Int(CPU_STATE_SYSTEM)])
            let idle = Double(ticks[base + Int(CPU_STATE_IDLE)] &- previousTicks[base + Int(CPU_STATE_IDLE)])
            let nice = Double(ticks[base + Int(CPU_STATE_NICE)] &- previousTicks[base + Int(CPU_STATE_NICE)])
            let elapsed = user + system + idle + nice

            totals.user += user
            totals.system += system
            totals.nice += nice
            totals.idle += idle
            perCore.append(elapsed > 0 ? ((user + system + nice) / elapsed).clamped01 : 0)
        }

        let elapsed = totals.user + totals.system + totals.nice + totals.idle
        guard elapsed > 0 else {
            return CPUUsage(
                perCore: perCore,
                performanceCoreCount: performanceCoreCount,
                efficiencyCoreCount: efficiencyCoreCount,
                loadAverage: Self.loadAverage()
            )
        }

        return CPUUsage(
            user: (totals.user / elapsed).clamped01,
            system: (totals.system / elapsed).clamped01,
            nice: (totals.nice / elapsed).clamped01,
            idle: (totals.idle / elapsed).clamped01,
            perCore: perCore,
            performanceCoreCount: performanceCoreCount,
            efficiencyCoreCount: efficiencyCoreCount,
            loadAverage: Self.loadAverage()
        )
    }

    /// Flattened `[core0.user, core0.system, core0.idle, core0.nice, core1.user, …]` tick counters.
    private static func readTicks() -> [UInt32]? {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        return (0..<Int(infoCount)).map { UInt32(bitPattern: info[$0]) }
    }

    private static func loadAverage() -> [Double] {
        var averages = [Double](repeating: 0, count: 3)
        let count = getloadavg(&averages, 3)
        guard count > 0 else { return [] }
        return Array(averages.prefix(Int(count)))
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}
