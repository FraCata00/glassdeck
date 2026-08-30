import Foundation
import Testing
@testable import GlassDeckKit

/// These run against the machine executing the tests, so they assert on ranges
/// and invariants rather than on exact numbers.
@Suite("Live sampling")
struct SamplingTests {
    @Test("The engine reports plausible values for this Mac")
    func engineProducesPlausibleSnapshot() async throws {
        let engine = MetricsEngine()

        // The first sample only primes the tick baselines.
        _ = await engine.sample()
        try await Task.sleep(for: .milliseconds(400))
        let snapshot = await engine.sample()

        #expect((0...1).contains(snapshot.cpu.total))
        #expect(snapshot.cpu.perCore.count == ProcessInfo.processInfo.activeProcessorCount)
        #expect(snapshot.cpu.perCore.allSatisfy { (0...1).contains($0) })

        #expect(snapshot.memory.total == ProcessInfo.processInfo.physicalMemory)
        #expect(snapshot.memory.used > 0)
        #expect(snapshot.memory.used < snapshot.memory.total)

        #expect(snapshot.disk.total > 0)
        #expect(snapshot.disk.free <= snapshot.disk.total)
        #expect(snapshot.disk.readBytesPerSecond >= 0)

        #expect(snapshot.network.downloadBytesPerSecond >= 0)
        #expect(snapshot.gpu.utilisation >= 0)
    }

    @Test("Every fan the SMC reports has a sane rated range")
    func fansAreConsistent() {
        let usage = FanSampler().sample()
        guard usage.isAvailable else { return }  // Fanless Mac: nothing to assert.

        for fan in usage.fans {
            #expect(fan.maximumRPM > fan.minimumRPM)
            #expect(fan.rpm >= 0)
            #expect(fan.rpm <= fan.maximumRPM * 1.2)
            #expect((0...1).contains(fan.fraction))
        }
    }

    @Test("Battery readings stay inside their own bounds")
    func batteryIsConsistent() {
        let battery = BatterySampler().sample()
        guard battery.isAvailable else { return }  // Desktop Mac.

        #expect((0...1).contains(battery.fraction))
        #expect((0...100).contains(battery.percentage))
        if battery.isCharging { #expect(battery.isPluggedIn) }
    }

    @Test("The monitor keeps a bounded history per metric")
    @MainActor
    func monitorHistory() async {
        let monitor = SystemMonitor(interval: 0.1)
        await monitor.refreshNow()
        await monitor.refreshNow()

        let history = monitor.history(for: .cpu)
        #expect(history.count == 2)
        #expect(history.count <= SystemMonitor.historyLength)
        #expect(monitor.snapshot.timestamp.timeIntervalSinceNow > -5)
    }
}
