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
    public var thermal: ThermalUsage
    public var power: PowerUsage
    /// Not a metric — a list of devices, each with its own charge — but sampled
    /// on the same tick, so it rides in the same snapshot. See `ModuleKind`.
    public var bluetooth: BluetoothStatus

    public init(
        timestamp: Date = Date(),
        cpu: CPUUsage = .zero,
        gpu: GPUUsage = .zero,
        memory: MemoryUsage = .zero,
        disk: DiskUsage = .zero,
        network: NetworkThroughput = .zero,
        fans: FanUsage = .unavailable,
        battery: BatteryUsage = .unavailable,
        thermal: ThermalUsage = .unavailable,
        power: PowerUsage = .unavailable,
        bluetooth: BluetoothStatus = .unavailable
    ) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.gpu = gpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.fans = fans
        self.battery = battery
        self.thermal = thermal
        self.power = power
        self.bluetooth = bluetooth
    }

    public static let empty = MetricsSnapshot()

    /// The headline fraction (0...1) for a metric kind, used by gauges and the Touch Bar.
    public func fraction(for kind: MetricKind) -> Double {
        switch kind {
        case .cpu: cpu.total
        case .gpu: gpu.utilisation
        case .memory: memory.usedFraction
        case .disk: disk.loadFraction
        case .network: network.loadFraction
        case .fans: fans.loadFraction
        case .battery: battery.fraction
        case .temperature: thermal.fraction
        case .power: power.fraction
        }
    }

    /// Whether this machine can report the metric at all: fanless Macs have no
    /// fan reading, desktops have no battery.
    public func supports(_ kind: MetricKind) -> Bool {
        switch kind {
        case .fans: fans.isAvailable
        case .battery: battery.isAvailable
        case .temperature: thermal.isAvailable
        case .power: power.isAvailable
        case .gpu: gpu.isAvailable
        case .cpu, .memory, .disk, .network: true
        }
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


/// One labelled number in a metric's detail view.
public struct MetricDetail: Sendable, Equatable, Identifiable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var id: String { label }
}
