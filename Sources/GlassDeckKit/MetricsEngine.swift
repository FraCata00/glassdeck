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

    private let processes = ProcessSampler()

    /// The samplers that need the SMC, built the first time a sample is taken.
    ///
    /// Standing them up means enumerating every key the SMC publishes — about
    /// 1800 of them, some 50 ms. An actor's `init` runs on whoever creates it,
    /// and that is `SystemMonitor` on the main actor at launch, so doing this
    /// eagerly charged the menu bar 50 ms of blocked main thread before it could
    /// draw. Everything below is reached only from actor-isolated methods, which
    /// run on the actor's own executor.
    private lazy var sensors: SMCSamplers = {
        // One SMC connection, shared by every sampler that needs it, and one
        // sensor catalogue built from it.
        let smc = SMCService()
        let catalogue = SensorCatalogue(smc: smc)
        return SMCSamplers(
            fans: FanSampler(smc: smc),
            thermal: ThermalSampler(smc: smc, catalogue: catalogue),
            power: PowerSampler(smc: smc, catalogue: catalogue)
        )
    }()

    private struct SMCSamplers {
        let fans: FanSampler
        let thermal: ThermalSampler
        let power: PowerSampler
    }

    public init() {}

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
            fans: sensors.fans.sample(at: now),
            battery: battery.sample(),
            thermal: sensors.thermal.sample(at: now),
            power: sensors.power.sample(at: now)
        )
    }

    /// Top CPU consumers. Sampled separately because it is only needed while the
    /// dashboard is on screen.
    public func topProcesses(limit: Int = 5) -> [ProcessSample] {
        processes.sample(limit: limit)
    }
}
