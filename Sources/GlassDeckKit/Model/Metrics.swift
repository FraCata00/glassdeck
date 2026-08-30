import Foundation

/// A single, immutable reading of every system metric GlassDeck tracks.
///
/// Snapshots are value types so they can cross actor boundaries freely: the
/// sampling engine produces them off the main actor and the UI consumes them on it.
public struct MetricsSnapshot: Sendable, Equatable {
    public var timestamp: Date
    public var cpu: CPUUsage
    public var gpu: GPUUsage
    public var memory: MemoryUsage
    public var disk: DiskUsage
    public var network: NetworkThroughput
    public var fans: FanUsage
    public var battery: BatteryUsage

    public init(
        timestamp: Date = Date(),
        cpu: CPUUsage = .zero,
        gpu: GPUUsage = .zero,
        memory: MemoryUsage = .zero,
        disk: DiskUsage = .zero,
        network: NetworkThroughput = .zero,
        fans: FanUsage = .unavailable,
        battery: BatteryUsage = .unavailable
    ) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.gpu = gpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.fans = fans
        self.battery = battery
    }

    public static let empty = MetricsSnapshot()

    /// The headline fraction (0...1) for a metric kind, used by gauges and the Touch Bar.
    public func fraction(for kind: MetricKind) -> Double {
        switch kind {
        case .cpu: cpu.total
        case .gpu: gpu.utilisation
        case .memory: memory.usedFraction
        case .disk: disk.usedFraction
        case .network: network.loadFraction
        case .fans: fans.loadFraction
        case .battery: battery.fraction
        }
    }

    /// Whether this machine can report the metric at all: fanless Macs have no
    /// fan reading, desktops have no battery.
    public func supports(_ kind: MetricKind) -> Bool {
        switch kind {
        case .fans: fans.isAvailable
        case .battery: battery.isAvailable
        case .gpu: gpu.isAvailable
        case .cpu, .memory, .disk, .network: true
        }
    }

    /// The short, human readable value shown under a gauge (e.g. `42%`, `9.1 GB`).
    public func headline(for kind: MetricKind) -> String {
        switch kind {
        case .cpu: ValueFormatter.percent(cpu.total)
        case .gpu: gpu.isAvailable ? ValueFormatter.percent(gpu.utilisation) : "n/a"
        case .memory: ValueFormatter.bytes(memory.used)
        case .disk: ValueFormatter.bytes(disk.used)
        case .network: ValueFormatter.rate(network.downloadBytesPerSecond)
        case .fans: fans.headline
        case .battery: battery.headline
        }
    }

    /// The secondary caption shown under the headline.
    public func caption(for kind: MetricKind) -> String {
        switch kind {
        case .cpu:
            "\(ValueFormatter.percent(cpu.user)) user · \(ValueFormatter.percent(cpu.system)) sys"
        case .gpu:
            gpu.isAvailable ? gpu.name : "no accelerator"
        case .memory:
            "\(ValueFormatter.bytes(memory.total)) total · \(ValueFormatter.bytes(memory.swapUsed)) swap"
        case .disk:
            "\(ValueFormatter.bytes(disk.free)) free of \(ValueFormatter.bytes(disk.total))"
        case .network:
            "↓ \(ValueFormatter.rate(network.downloadBytesPerSecond)) ↑ \(ValueFormatter.rate(network.uploadBytesPerSecond))"
        case .fans:
            fans.caption
        case .battery:
            battery.caption
        }
    }
}

/// Aggregate and per-core processor load, expressed as fractions in `0...1`.
public struct CPUUsage: Sendable, Equatable {
    public var user: Double
    public var system: Double
    public var nice: Double
    public var idle: Double
    public var perCore: [Double]
    public var performanceCoreCount: Int
    public var efficiencyCoreCount: Int
    public var loadAverage: [Double]

    public init(
        user: Double = 0,
        system: Double = 0,
        nice: Double = 0,
        idle: Double = 1,
        perCore: [Double] = [],
        performanceCoreCount: Int = 0,
        efficiencyCoreCount: Int = 0,
        loadAverage: [Double] = []
    ) {
        self.user = user
        self.system = system
        self.nice = nice
        self.idle = idle
        self.perCore = perCore
        self.performanceCoreCount = performanceCoreCount
        self.efficiencyCoreCount = efficiencyCoreCount
        self.loadAverage = loadAverage
    }

    public static let zero = CPUUsage()

    /// Busy fraction of the machine: everything that is not idle.
    public var total: Double { (user + system + nice).clamped01 }

    /// Mean load of the performance cluster, or `nil` on machines without one.
    public var performanceClusterLoad: Double? {
        guard performanceCoreCount > 0, perCore.count >= performanceCoreCount else { return nil }
        return perCore.prefix(performanceCoreCount).mean
    }

    /// Mean load of the efficiency cluster, or `nil` when the topology is unknown.
    public var efficiencyClusterLoad: Double? {
        guard efficiencyCoreCount > 0, perCore.count == performanceCoreCount + efficiencyCoreCount else { return nil }
        return perCore.suffix(efficiencyCoreCount).mean
    }
}

/// Graphics utilisation read from the IOKit accelerator registry.
public struct GPUUsage: Sendable, Equatable {
    public var name: String
    public var utilisation: Double
    public var rendererUtilisation: Double
    public var tilerUtilisation: Double
    public var allocatedMemory: UInt64
    public var isAvailable: Bool

    public init(
        name: String = "GPU",
        utilisation: Double = 0,
        rendererUtilisation: Double = 0,
        tilerUtilisation: Double = 0,
        allocatedMemory: UInt64 = 0,
        isAvailable: Bool = false
    ) {
        self.name = name
        self.utilisation = utilisation
        self.rendererUtilisation = rendererUtilisation
        self.tilerUtilisation = tilerUtilisation
        self.allocatedMemory = allocatedMemory
        self.isAvailable = isAvailable
    }

    public static let zero = GPUUsage()
}

/// Physical memory breakdown, mirroring the categories Activity Monitor reports.
public struct MemoryUsage: Sendable, Equatable {
    public var total: UInt64
    public var active: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var inactive: UInt64
    public var free: UInt64
    public var swapUsed: UInt64
    public var swapTotal: UInt64

    public init(
        total: UInt64 = 0,
        active: UInt64 = 0,
        wired: UInt64 = 0,
        compressed: UInt64 = 0,
        inactive: UInt64 = 0,
        free: UInt64 = 0,
        swapUsed: UInt64 = 0,
        swapTotal: UInt64 = 0
    ) {
        self.total = total
        self.active = active
        self.wired = wired
        self.compressed = compressed
        self.inactive = inactive
        self.free = free
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
    }

    public static let zero = MemoryUsage()

    /// Memory that cannot be reclaimed on demand — the number users think of as "used".
    public var used: UInt64 { active &+ wired &+ compressed }

    public var usedFraction: Double {
        total == 0 ? 0 : (Double(used) / Double(total)).clamped01
    }

    /// A coarse stand-in for the memory pressure graph: wired + compressed against total.
    public var pressure: Double {
        total == 0 ? 0 : (Double(wired &+ compressed) / Double(total)).clamped01
    }
}

/// Capacity and throughput of the boot volume.
public struct DiskUsage: Sendable, Equatable {
    public var volumeName: String
    public var total: UInt64
    public var free: UInt64
    public var readBytesPerSecond: Double
    public var writeBytesPerSecond: Double

    public init(
        volumeName: String = "Macintosh HD",
        total: UInt64 = 0,
        free: UInt64 = 0,
        readBytesPerSecond: Double = 0,
        writeBytesPerSecond: Double = 0
    ) {
        self.volumeName = volumeName
        self.total = total
        self.free = free
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
    }

    public static let zero = DiskUsage()

    public var used: UInt64 { total > free ? total - free : 0 }

    public var usedFraction: Double {
        total == 0 ? 0 : (Double(used) / Double(total)).clamped01
    }
}

/// Aggregate traffic across all active interfaces.
public struct NetworkThroughput: Sendable, Equatable {
    public var downloadBytesPerSecond: Double
    public var uploadBytesPerSecond: Double

    public init(downloadBytesPerSecond: Double = 0, uploadBytesPerSecond: Double = 0) {
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }

    public static let zero = NetworkThroughput()

    /// Traffic mapped onto `0...1` with a 12.5 MB/s (≈100 Mbit) reference ceiling,
    /// so the gauge stays readable on everyday connections.
    public var loadFraction: Double {
        let reference = 12_500_000.0
        return (max(downloadBytesPerSecond, uploadBytesPerSecond) / reference).clamped01
    }
}

/// A process as reported by the top-consumers sampler.
public struct ProcessSample: Sendable, Equatable, Identifiable {
    public var id: Int32
    public var name: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64

    public init(id: Int32, name: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.id = id
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}


/// A single fan as reported by the SMC.
public struct Fan: Sendable, Equatable, Identifiable {
    public var index: Int
    public var rpm: Double
    public var minimumRPM: Double
    public var maximumRPM: Double

    public init(index: Int, rpm: Double, minimumRPM: Double, maximumRPM: Double) {
        self.index = index
        self.rpm = rpm
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
    }

    public var id: Int { index }

    /// Where the fan sits inside its own rated range. A stopped fan reads `0`
    /// rather than being mapped onto the bottom of the range.
    public var fraction: Double {
        guard rpm > 0, maximumRPM > minimumRPM else { return 0 }
        return ((rpm - minimumRPM) / (maximumRPM - minimumRPM)).clamped01
    }
}

/// Every fan in the machine, or a marker that this Mac has none.
public struct FanUsage: Sendable, Equatable {
    public var fans: [Fan]
    /// `false` on fanless Macs and wherever the SMC cannot be reached.
    public var isAvailable: Bool

    public init(fans: [Fan] = [], isAvailable: Bool = false) {
        self.fans = fans
        self.isAvailable = isAvailable
    }

    public static let unavailable = FanUsage()

    /// The busiest fan drives the gauge — it is the one making the noise.
    public var loadFraction: Double { fans.map(\.fraction).max() ?? 0 }

    public var topRPM: Double { fans.map(\.rpm).max() ?? 0 }

    public var headline: String {
        guard isAvailable else { return "n/a" }
        guard topRPM > 0 else { return "idle" }
        return "\(Int(topRPM.rounded())) rpm"
    }

    public var caption: String {
        guard isAvailable else { return "fanless Mac" }
        if fans.count > 1 {
            return fans.map { "\(Int($0.rpm.rounded()))" }.joined(separator: " · ") + " rpm"
        }
        guard let fan = fans.first else { return "no fan" }
        return "range \(Int(fan.minimumRPM))–\(Int(fan.maximumRPM)) rpm"
    }
}


/// Charge level and power state of the internal battery.
public struct BatteryUsage: Sendable, Equatable {
    public var fraction: Double
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public var minutesRemaining: Int?
    /// `false` on Macs without an internal battery.
    public var isAvailable: Bool

    public init(
        fraction: Double = 0,
        isCharging: Bool = false,
        isPluggedIn: Bool = false,
        minutesRemaining: Int? = nil,
        isAvailable: Bool = false
    ) {
        self.fraction = fraction
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.minutesRemaining = minutesRemaining
        self.isAvailable = isAvailable
    }

    public static let unavailable = BatteryUsage()

    public var percentage: Int { Int((fraction * 100).rounded()) }

    public var headline: String { isAvailable ? "\(percentage)%" : "n/a" }

    public var caption: String {
        guard isAvailable else { return "no battery" }
        let state = isCharging ? "charging" : (isPluggedIn ? "on power" : "on battery")
        guard let minutesRemaining else { return state }
        let hours = minutesRemaining / 60
        let minutes = minutesRemaining % 60
        let remaining = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        return isCharging ? "\(state) · \(remaining) to full" : "\(state) · \(remaining) left"
    }

    /// SF Symbol matching the current level, mirroring the system's own glyph set.
    public var symbolName: String {
        guard isAvailable else { return "battery.slash" }
        if isCharging { return "battery.100.bolt" }
        switch fraction {
        case ..<0.13: return "battery.0"
        case ..<0.38: return "battery.25"
        case ..<0.63: return "battery.50"
        case ..<0.88: return "battery.75"
        default: return "battery.100"
        }
    }
}
