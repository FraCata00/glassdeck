import Foundation
import Testing
@testable import GlassDeckKit

@Suite("Coarse accumulation")
struct CoarseAccumulatorTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func snapshot(
        at seconds: TimeInterval,
        cpu user: Double,
        cores: [Double] = [],
        gpu: Double = 0,
        read: Double = 0,
        download: Double = 0,
        celsius: Double? = nil
    ) -> MetricsSnapshot {
        MetricsSnapshot(
            timestamp: start.addingTimeInterval(seconds),
            cpu: CPUUsage(user: user, idle: 1 - user, perCore: cores),
            gpu: GPUUsage(utilisation: gpu, isAvailable: true),
            disk: DiskUsage(readBytesPerSecond: read),
            network: NetworkThroughput(downloadBytesPerSecond: download),
            thermal: ThermalUsage(cpu: celsius, isAvailable: celsius != nil)
        )
    }

    @Test("Every sample since the last publication counts, weighted by the time it covers")
    func weightedMean() {
        var accumulator = CoarseAccumulator()
        accumulator.add(snapshot(at: 0, cpu: 0))
        _ = accumulator.drain()

        // A burst in the sample that the throttle used to drop: 1.5 s at 90 %
        // then 1.5 s at 10 % is three seconds at 50 %, not 10 %.
        accumulator.add(snapshot(at: 1.5, cpu: 0.9, cores: [1, 0.8], gpu: 0.6, read: 3_000, download: 300))
        accumulator.add(snapshot(at: 3.0, cpu: 0.1, cores: [0, 0.2], gpu: 0.2, read: 1_000, download: 100))
        let published = accumulator.drain()

        #expect(abs(published.cpu.user - 0.5) < 1e-9)
        #expect(abs(published.cpu.idle - 0.5) < 1e-9)
        #expect(published.cpu.perCore.count == 2)
        #expect(abs(published.cpu.perCore[0] - 0.5) < 1e-9)
        #expect(abs(published.cpu.perCore[1] - 0.5) < 1e-9)
        #expect(abs(published.gpu.utilisation - 0.4) < 1e-9)
        #expect(abs(published.disk.readBytesPerSecond - 2_000) < 1e-9)
        #expect(abs(published.network.downloadBytesPerSecond - 200) < 1e-9)
        #expect(published.timestamp == start.addingTimeInterval(3))
    }

    @Test("Uneven spans weigh in proportion to the time they cover")
    func unevenSpans() {
        var accumulator = CoarseAccumulator()
        accumulator.add(snapshot(at: 0, cpu: 0))
        _ = accumulator.drain()
        accumulator.add(snapshot(at: 3, cpu: 1))
        accumulator.add(snapshot(at: 4, cpu: 0))
        #expect(abs(accumulator.drain().cpu.user - 0.75) < 1e-9)
    }

    @Test("Levels are not averaged: they are the latest reading")
    func levelsAreLatest() {
        var accumulator = CoarseAccumulator()
        accumulator.add(snapshot(at: 0, cpu: 0, celsius: 40))
        _ = accumulator.drain()
        accumulator.add(snapshot(at: 1, cpu: 0, celsius: 50))
        accumulator.add(snapshot(at: 2, cpu: 0, celsius: 60))
        #expect(accumulator.drain().thermal.cpu == 60)
    }

    @Test("A single pending sample, the first one included, is published as it is")
    func singleSample() {
        var accumulator = CoarseAccumulator()
        let first = snapshot(at: 0, cpu: 0.3, cores: [0.3])
        accumulator.add(first)
        #expect(accumulator.drain() == first)

        let second = snapshot(at: 1.5, cpu: 0.7, cores: [0.7])
        accumulator.add(second)
        #expect(accumulator.drain() == second)
    }

    @Test("A core count that changes mid-window keeps the latest per-core reading")
    func coreCountChange() {
        var accumulator = CoarseAccumulator()
        accumulator.add(snapshot(at: 0, cpu: 0))
        _ = accumulator.drain()
        accumulator.add(snapshot(at: 1, cpu: 0.2, cores: [0.2]))
        accumulator.add(snapshot(at: 2, cpu: 0.4, cores: [0.4, 0.4]))
        #expect(accumulator.drain().cpu.perCore == [0.4, 0.4])
    }

    @Test("A sample after a long park does not drown out the rest of its window")
    func longGapIsCapped() {
        var accumulator = CoarseAccumulator()
        accumulator.add(snapshot(at: 0, cpu: 0))
        _ = accumulator.drain()
        // Back from an hour of display sleep, then one ordinary tick.
        accumulator.add(snapshot(at: 3_600, cpu: 0))
        accumulator.add(snapshot(at: 3_601, cpu: 1))
        let user = accumulator.drain().cpu.user
        #expect(user > 0.05)
    }
}
