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
        let usage = FanSampler(smc: SMCService()).sample()
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

    @Test("Discovered sensors report plausible temperatures and power")
    func sensorsAreConsistent() {
        let smc = SMCService()
        let catalogue = SensorCatalogue(smc: smc)

        let thermal = ThermalSampler(smc: smc, catalogue: catalogue).sample()
        if thermal.isAvailable {
            #expect(thermal.sensorCount > 0)
            for reading in [thermal.cpu, thermal.gpu, thermal.battery, thermal.enclosure].compactMap({ $0 }) {
                #expect(SensorCatalogue.plausibleTemperature.contains(reading))
            }
            #expect((0...1).contains(thermal.fraction))
        }

        let power = PowerSampler(smc: smc, catalogue: catalogue).sample()
        if power.isAvailable {
            #expect(power.watts > 0)
            // A Mac drawing more than its adapter can supply would be a bad reading.
            #expect(power.watts < 400)
            #expect((0...1).contains(power.fraction))
        }
    }

    @Test("Both open views have to close before the process scan stops")
    @MainActor
    func processObserversAreCounted() {
        let monitor = SystemMonitor(interval: 1)
        #expect(monitor.samplesProcesses == false)

        monitor.beginSamplingProcesses()   // the menu bar panel opens
        monitor.beginSamplingProcesses()   // the dashboard opens too
        #expect(monitor.samplesProcesses)

        monitor.endSamplingProcesses()     // the panel closes
        #expect(monitor.samplesProcesses)  // the dashboard still wants the list

        monitor.endSamplingProcesses()
        #expect(monitor.samplesProcesses == false)
    }

    @Test("An unbalanced end cannot drive the count below zero")
    @MainActor
    func processObserverCountFloorsAtZero() {
        let monitor = SystemMonitor(interval: 1)
        monitor.endSamplingProcesses()
        monitor.endSamplingProcesses()

        monitor.beginSamplingProcesses()
        #expect(monitor.samplesProcesses)
        monitor.endSamplingProcesses()
        #expect(monitor.samplesProcesses == false)
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

/// Reading every thermometer costs about 19 ms — more than every other metric
/// put together — and temperature moves with the machine's thermal mass, not
/// with the sampling cadence.
@Suite("Thermal sampling cadence")
struct ThermalCadenceTests {
    @Test("A reading stands for the refresh interval, then the sensors are read again")
    func readingsAreReused() {
        let smc = SMCService()
        let sampler = ThermalSampler(
            smc: smc,
            catalogue: SensorCatalogue(smc: smc),
            refreshInterval: 5
        )
        let start = Date()

        _ = sampler.sample(at: start)
        #expect(sampler.readCount == 1)

        // Ticks inside the window reuse it, whatever the cadence.
        for offset in [1.5, 3.0, 4.5, 4.99] {
            _ = sampler.sample(at: start.addingTimeInterval(offset))
        }
        #expect(sampler.readCount == 1)

        // The first tick past it reads again.
        _ = sampler.sample(at: start.addingTimeInterval(5))
        #expect(sampler.readCount == 2)

        _ = sampler.sample(at: start.addingTimeInterval(9.9))
        #expect(sampler.readCount == 2)
    }

    @Test("A reused reading is the same reading, not a fresh zero")
    func reusedReadingIsUnchanged() {
        let smc = SMCService()
        let sampler = ThermalSampler(smc: smc, catalogue: SensorCatalogue(smc: smc), refreshInterval: 5)
        let start = Date()

        let first = sampler.sample(at: start)
        #expect(sampler.sample(at: start.addingTimeInterval(2)) == first)
    }
}
