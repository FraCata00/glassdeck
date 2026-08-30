import Foundation

/// Serialises every sampler on a single background actor.
///
/// The samplers keep mutable tick baselines and are not thread safe on their own;
/// confining them to this actor is what makes the whole pipeline `Sendable`.
public actor MetricsEngine {
    private let cpu = CPUSampler()
    private let gpu = GPUSampler()
    private let memory = MemorySampler()
    private let disk = DiskSampler()
    private let network = NetworkSampler()
    private let battery = BatterySampler()

    // One SMC connection, shared by every sampler that needs it, and one sensor
    // catalogue built from it at start-up.
    private let smc = SMCService()
    private let fans: FanSampler
    private let thermal: ThermalSampler
    private let power: PowerSampler
    private let processes = ProcessSampler()

    public init() {
        let catalogue = SensorCatalogue(smc: smc)
        fans = FanSampler(smc: smc)
        thermal = ThermalSampler(smc: smc, catalogue: catalogue)
        power = PowerSampler(smc: smc, catalogue: catalogue)
    }

    /// Reads every metric once. The first call primes the delta baselines and
    /// therefore reports zero for the rate-based metrics.
    public func sample() -> MetricsSnapshot {
        let now = Date()
        return MetricsSnapshot(
            timestamp: now,
            cpu: cpu.sample(),
            gpu: gpu.sample(),
            memory: memory.sample(),
            disk: disk.sample(at: now),
            network: network.sample(at: now),
            fans: fans.sample(),
            battery: battery.sample(),
            thermal: thermal.sample(),
            power: power.sample()
        )
    }

    /// Top CPU consumers. Sampled separately because it is only needed while the
    /// dashboard is on screen.
    public func topProcesses(limit: Int = 5) -> [ProcessSample] {
        processes.sample(limit: limit)
    }
}
