import Darwin
import Foundation
import IOKit

/// Reads per-core processor load from the Mach host and turns consecutive tick
/// counters into usage fractions.
///
/// The kernel exposes monotonically increasing tick counters, so a single reading
/// is meaningless: the first `sample()` primes the baseline and returns zeroes.
public final class CPUSampler {
    private var previousTicks: [UInt32] = []
    private let statesPerCore = Int(CPU_STATE_MAX)

    /// The cluster of each logical CPU, in tick-counter order; empty on Intel.
    ///
    /// The topology cannot change while the machine is up, so it is read once.
    public let coreKinds: [CoreKind]

    public init() {
        coreKinds = Self.coreKinds(
            fromDeviceTree: Self.deviceTreeCoreKinds(),
            performanceCount: Self.sysctlInt("hw.perflevel0.logicalcpu") ?? 0,
            efficiencyCount: Self.sysctlInt("hw.perflevel1.logicalcpu") ?? 0
        )
    }

    /// Reconciles the device tree's per-core clusters with the kernel's counts.
    ///
    /// The device tree is the authority: it says, for each logical CPU, which
    /// cluster it sits in. Where it cannot be read, or its numbering has a gap,
    /// the counts are laid out efficiency first, which is how every Apple
    /// silicon chip so far numbers its cores.
    static func coreKinds(
        fromDeviceTree tree: [Int: CoreKind],
        performanceCount: Int,
        efficiencyCount: Int
    ) -> [CoreKind] {
        let ordered = (0..<tree.count).compactMap { tree[$0] }
        if !tree.isEmpty, ordered.count == tree.count { return ordered }
        guard performanceCount > 0, efficiencyCount > 0 else { return [] }
        return Array(repeating: .efficiency, count: efficiencyCount)
            + Array(repeating: .performance, count: performanceCount)
    }

    /// `IODeviceTree:/cpus` holds one node per logical CPU carrying its
    /// `logical-cpu-id` and a `cluster-type` of `E` or `P`. Empty on Intel,
    /// whose device tree has no such nodes.
    private static func deviceTreeCoreKinds() -> [Int: CoreKind] {
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard cpus != 0 else { return [:] }
        defer { IOObjectRelease(cpus) }

        var iterator = io_iterator_t()
        guard IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }

        var kinds: [Int: CoreKind] = [:]
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let id = integer(property: "logical-cpu-id", of: entry),
                  let cluster = string(property: "cluster-type", of: entry)
            else { continue }
            switch cluster {
            case "P": kinds[id] = .performance
            case "E": kinds[id] = .efficiency
            default: continue
            }
        }
        return kinds
    }

    private static func property(_ name: String, of entry: io_registry_entry_t) -> Any? {
        IORegistryEntryCreateCFProperty(entry, name as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// Device-tree integers are little-endian `Data` on some releases and
    /// numbers on others, so both shapes are read.
    private static func integer(property name: String, of entry: io_registry_entry_t) -> Int? {
        switch property(name, of: entry) {
        case let number as NSNumber:
            return number.intValue
        case let data as Data where data.count >= 4:
            return Int(data.prefix(4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) })
        default:
            return nil
        }
    }

    /// A NUL-terminated C string stored as `Data`, or a plain string.
    private static func string(property name: String, of entry: io_registry_entry_t) -> String? {
        switch property(name, of: entry) {
        case let string as String:
            return string
        case let data as Data:
            return String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
        default:
            return nil
        }
    }

    public func sample() -> CPUUsage {
        guard let ticks = Self.readTicks() else { return .zero }
        defer { previousTicks = ticks }

        guard previousTicks.count == ticks.count, !previousTicks.isEmpty else {
            return CPUUsage(
                perCore: Array(repeating: 0, count: ticks.count / statesPerCore),
                coreKinds: coreKinds,
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
                coreKinds: coreKinds,
                loadAverage: Self.loadAverage()
            )
        }

        return CPUUsage(
            user: (totals.user / elapsed).clamped01,
            system: (totals.system / elapsed).clamped01,
            nice: (totals.nice / elapsed).clamped01,
            idle: (totals.idle / elapsed).clamped01,
            perCore: perCore,
            coreKinds: coreKinds,
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
