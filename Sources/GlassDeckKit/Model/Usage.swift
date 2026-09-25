import Foundation

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
    /// Anonymous pages an app has actually asked for, net of what it has marked
    /// purgeable — what Activity Monitor calls "App Memory".
    public var appMemory: UInt64
    public var active: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var inactive: UInt64
    public var free: UInt64
    public var swapUsed: UInt64
    public var swapTotal: UInt64

    public init(
        total: UInt64 = 0,
        appMemory: UInt64 = 0,
        active: UInt64 = 0,
        wired: UInt64 = 0,
        compressed: UInt64 = 0,
        inactive: UInt64 = 0,
        free: UInt64 = 0,
        swapUsed: UInt64 = 0,
        swapTotal: UInt64 = 0
    ) {
        self.total = total
        self.appMemory = appMemory
        self.active = active
        self.wired = wired
        self.compressed = compressed
        self.inactive = inactive
        self.free = free
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
    }

    public static let zero = MemoryUsage()

    /// What Activity Monitor calls "Memory Used": app memory, plus the pages the
    /// kernel has wired down, plus whatever the compressor is holding.
    ///
    /// `active` is deliberately not part of this. It counts file-backed pages
    /// that are in use but evictable on demand, so building the figure from it
    /// both counts cache as used and misses anonymous pages that have gone
    /// inactive — a number close to the right one for the wrong reasons.
    public var used: UInt64 { appMemory &+ wired &+ compressed }

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

    /// Full scale for the activity gauge, tracked the same way the network's is.
    public var referenceBytesPerSecond: Double

    /// Slowest full scale the activity gauge will use.
    public static let minimumReference = 20_000_000.0

    public init(
        volumeName: String = "Macintosh HD",
        total: UInt64 = 0,
        free: UInt64 = 0,
        readBytesPerSecond: Double = 0,
        writeBytesPerSecond: Double = 0,
        referenceBytesPerSecond: Double = DiskUsage.minimumReference
    ) {
        self.volumeName = volumeName
        self.total = total
        self.free = free
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
        self.referenceBytesPerSecond = referenceBytesPerSecond
    }

    public static let zero = DiskUsage()

    public var used: UInt64 { total > free ? total - free : 0 }

    /// How full the volume is. Still reported — it is just no longer what the
    /// graph draws, since capacity barely moves and made the sparkline a flat
    /// line while the disk was plainly busy.
    public var usedFraction: Double {
        total == 0 ? 0 : (Double(used) / Double(total)).clamped01
    }

    public var busiestBytesPerSecond: Double {
        max(readBytesPerSecond, writeBytesPerSecond)
    }

    public var loadFraction: Double {
        let reference = max(referenceBytesPerSecond, Self.minimumReference)
        return (busiestBytesPerSecond / reference).clamped01
    }
}

/// Aggregate traffic across all active interfaces.
public struct NetworkThroughput: Sendable, Equatable {
    public var downloadBytesPerSecond: Double
    public var uploadBytesPerSecond: Double
    /// Full scale for the gauge: the fastest this machine has recently been seen
    /// to move bytes. A fixed ceiling cannot suit both a 10 Mbit line and a
    /// 10 Gbit one — at 100 Mbit, any real download pinned the gauge to full.
    public var referenceBytesPerSecond: Double

    /// Slowest full scale the gauge will use, so background chatter on an idle
    /// machine does not read as a busy network.
    public static let minimumReference = 1_250_000.0

    public init(
        downloadBytesPerSecond: Double = 0,
        uploadBytesPerSecond: Double = 0,
        referenceBytesPerSecond: Double = NetworkThroughput.minimumReference
    ) {
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.referenceBytesPerSecond = referenceBytesPerSecond
    }

    public static let zero = NetworkThroughput()

    public var busiestBytesPerSecond: Double {
        max(downloadBytesPerSecond, uploadBytesPerSecond)
    }

    public var loadFraction: Double {
        let reference = max(referenceBytesPerSecond, Self.minimumReference)
        return (busiestBytesPerSecond / reference).clamped01
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
}

/// What the machine's thermometers report, in degrees Celsius.
public struct ThermalUsage: Sendable, Equatable {
    public var cpu: Double?
    public var gpu: Double?
    public var battery: Double?
    public var enclosure: Double?
    /// How many sensors the catalogue found, shown so the reading can be trusted.
    public var sensorCount: Int
    public var isAvailable: Bool

    public init(
        cpu: Double? = nil,
        gpu: Double? = nil,
        battery: Double? = nil,
        enclosure: Double? = nil,
        sensorCount: Int = 0,
        isAvailable: Bool = false
    ) {
        self.cpu = cpu
        self.gpu = gpu
        self.battery = battery
        self.enclosure = enclosure
        self.sensorCount = sensorCount
        self.isAvailable = isAvailable
    }

    public static let unavailable = ThermalUsage()

    /// The reading the gauge shows: the hottest part of the machine.
    public var hottest: Double? {
        [cpu, gpu, battery, enclosure].compactMap { $0 }.max()
    }

    /// Mapped so that 30 °C reads as empty and 100 °C as full, which spans the
    /// range between idle and thermal throttling on every Mac.
    public var fraction: Double {
        guard let hottest else { return 0 }
        return ((hottest - 30) / 70).clamped01
    }
}

/// Instantaneous power draw of the whole machine.
public struct PowerUsage: Sendable, Equatable {
    public var watts: Double
    /// Rating of the attached power adapter, when the SMC reports one.
    public var adapterWatts: Double?
    public var isAvailable: Bool

    public init(watts: Double = 0, adapterWatts: Double? = nil, isAvailable: Bool = false) {
        self.watts = watts
        self.adapterWatts = adapterWatts
        self.isAvailable = isAvailable
    }

    public static let unavailable = PowerUsage()

    /// Full scale is the adapter's rating when it is known, since that is the
    /// most the machine can draw; otherwise a 60 W stand-in.
    public var referenceWatts: Double {
        guard let adapterWatts, adapterWatts > 5 else { return 60 }
        return adapterWatts
    }

    public var fraction: Double { (watts / referenceWatts).clamped01 }
}
