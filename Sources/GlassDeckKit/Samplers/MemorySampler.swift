import Darwin
import Foundation

/// Reads the Mach VM statistics and the kernel swap counters.
public final class MemorySampler {
    private let pageSize: UInt64
    private let physicalMemory: UInt64

    public init() {
        var size: vm_size_t = 0
        pageSize = host_page_size(mach_host_self(), &size) == KERN_SUCCESS ? UInt64(size) : 4096
        physicalMemory = ProcessInfo.processInfo.physicalMemory
    }

    public func sample() -> MemoryUsage {
        guard let stats = Self.vmStatistics() else {
            return MemoryUsage(total: physicalMemory)
        }

        let swap = Self.swapUsage()
        return MemoryUsage(
            total: physicalMemory,
            active: UInt64(stats.active_count) * pageSize,
            wired: UInt64(stats.wire_count) * pageSize,
            compressed: UInt64(stats.compressor_page_count) * pageSize,
            inactive: UInt64(stats.inactive_count) * pageSize,
            free: UInt64(stats.free_count) * pageSize,
            swapUsed: swap.used,
            swapTotal: swap.total
        )
    }

    private static func vmStatistics() -> vm_statistics64_data_t? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? stats : nil
    }

    private static func swapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_used, usage.xsu_total)
    }
}
