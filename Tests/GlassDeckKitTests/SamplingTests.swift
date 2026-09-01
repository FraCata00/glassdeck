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

    @Test("Whatever this Mac has paired reports charges inside their own bounds")
    func bluetoothIsConsistent() {
        let status = BluetoothSampler().sample(at: Date())
        guard status.isAvailable else { return }  // Nothing paired reports a battery.

        for device in status.devices {
            #expect(!device.address.isEmpty)
            #expect(!device.name.isEmpty)
            // A device is only listed at all because it reported something.
            #expect(!device.battery.isEmpty)
            for level in device.battery.levels {
                #expect((0.0...1.0).contains(level.value))
                #expect(level.value > 0)
            }
        }
        // The headline can only come from a device that is on the air.
        if let lowest = status.lowest {
            #expect(status.connected.contains { $0.battery.lowest == lowest })
        } else {
            #expect(status.connected.isEmpty)
        }
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

    @Test("A sensor published on four channels is counted once")
    func redundantChannelsCollapseToOne() {
        let keys = ["Tp9a", "Tp9b", "Tp9x", "Tp9z", "Tp4b", "Tp4z", "TB0T", "Th1H"]
        let kept = SensorCatalogue.oneChannelPerSensor(keys)

        // One key per sensor, and the preferred channel is the one kept.
        #expect(kept == ["TB0T", "Th1H", "Tp4b", "Tp9b"])
    }

    @Test("A sensor missing the preferred channel falls back in order")
    func fallsBackToTheNextChannel() {
        #expect(SensorCatalogue.oneChannelPerSensor(["Tp9z", "Tp9x", "Tp9a"]) == ["Tp9a"])
        #expect(SensorCatalogue.oneChannelPerSensor(["Tp9z", "Tp9x"]) == ["Tp9x"])
        #expect(SensorCatalogue.oneChannelPerSensor(["Tp9z"]) == ["Tp9z"])
    }

    @Test("Keys that carry no channel suffix are all kept")
    func intelKeysAreLeftAlone() {
        // An Intel Mac publishes TC0P, TC0D, TC0E and TC0F for one CPU: four
        // keys on one sensor stem, none of them a channel of the same reading.
        let intel = ["TC0P", "TC0D", "TC0E", "TC0F"]
        #expect(SensorCatalogue.oneChannelPerSensor(intel) == intel.sorted())
    }

    @Test("This Mac reports each thermometer once, not four times")
    func liveCatalogueHasNoRedundantChannels() {
        let catalogue = SensorCatalogue(smc: SMCService())
        let keys = catalogue.cpu + catalogue.gpu + catalogue.battery + catalogue.enclosure
        guard !keys.isEmpty else { return }  // No SMC: nothing to assert.

        // Keys with no channel suffix are a sensor of their own — an enclosure
        // `Ts0P` sits beside `Ts0b` — so only the channelled ones must be unique.
        let channelled = keys.filter { "abxz".contains($0.last ?? " ") }
        let sensors = channelled.map { String($0.dropLast()) }
        #expect(Set(sensors).count == sensors.count)
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

    @Test("The coarse snapshot is held back between publications")
    @MainActor
    func coarseSnapshotIsThrottled() async {
        let monitor = SystemMonitor(interval: 0.1)
        #expect(monitor.coarseSnapshot == .empty)

        // The first sample publishes straight away, so the menu bar is not blank
        // for the length of the coarse interval at launch.
        await monitor.refreshNow()
        let first = monitor.coarseSnapshot
        #expect(first != .empty)
        #expect(first == monitor.snapshot)

        // A second sample well inside the interval moves the fine snapshot but
        // not the coarse one — which is what keeps the status item still.
        await monitor.refreshNow()
        #expect(monitor.snapshot != first)
        #expect(monitor.coarseSnapshot == first)
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

/// The fans and the wattage go through the same SMC connection as the
/// thermometers, and change no faster: both reuse a reading rather than paying
/// for a round trip on every tick.
@Suite("SMC sampling cadence")
struct SMCCadenceTests {
    @Test("Fan readings are reused inside the refresh interval")
    func fanReadingsAreReused() {
        let sampler = FanSampler(smc: SMCService(), refreshInterval: 3)
        let start = Date()

        let first = sampler.sample(at: start)
        #expect(sampler.readCount == 1)

        for offset in [1.5, 2.99] {
            #expect(sampler.sample(at: start.addingTimeInterval(offset)) == first)
        }
        #expect(sampler.readCount == 1)

        _ = sampler.sample(at: start.addingTimeInterval(3))
        #expect(sampler.readCount == 2)
    }

    @Test("Power readings are reused inside the refresh interval")
    func powerReadingsAreReused() {
        let smc = SMCService()
        let sampler = PowerSampler(smc: smc, catalogue: SensorCatalogue(smc: smc), refreshInterval: 2)
        let start = Date()

        let first = sampler.sample(at: start)
        #expect(sampler.readCount == 1)
        #expect(sampler.sample(at: start.addingTimeInterval(1.5)) == first)
        #expect(sampler.readCount == 1)

        _ = sampler.sample(at: start.addingTimeInterval(2))
        #expect(sampler.readCount == 2)
    }

    @Test("A fanless Mac still reports unavailable rather than a stale reading")
    func fanlessMacIsHonest() {
        let sampler = FanSampler(smc: nil)
        let start = Date()

        #expect(sampler.sample(at: start).isAvailable == false)
        #expect(sampler.sample(at: start.addingTimeInterval(10)).isAvailable == false)
    }
}

/// Sampling into a dark screen costs a wake-up per tick and shows nobody
/// anything, and Low Power Mode is the user asking for exactly this restraint.
@Suite("Power-aware sampling")
struct PowerAwarenessTests {
    @Test("Parking keeps the intent to be running, so a wake resumes rather than restarts")
    @MainActor
    func suspendKeepsRunningIntent() {
        let monitor = SystemMonitor(interval: 1)
        monitor.start()
        #expect(monitor.isRunning)
        #expect(monitor.isSuspended == false)

        monitor.suspend()
        #expect(monitor.isSuspended)
        #expect(monitor.isRunning)  // still wanted, just not sampling

        monitor.resume()
        #expect(monitor.isSuspended == false)
        #expect(monitor.isRunning)
        monitor.stop()
    }

    @Test("Overlapping sleep and wake events are idempotent")
    @MainActor
    func repeatedEventsAreHarmless() {
        let monitor = SystemMonitor(interval: 1)
        monitor.start()

        // Sleeping the machine sends the screens to sleep too: both arrive.
        monitor.suspend()
        monitor.suspend()
        #expect(monitor.isSuspended)

        monitor.resume()
        monitor.resume()
        #expect(monitor.isSuspended == false)
        monitor.stop()
    }

    @Test("A full stop clears the parked state")
    @MainActor
    func stopClearsSuspension() {
        let monitor = SystemMonitor(interval: 1)
        monitor.start()
        monitor.suspend()
        monitor.stop()

        #expect(monitor.isRunning == false)
        #expect(monitor.isSuspended == false)

        // And a later start samples again instead of coming up parked.
        monitor.start()
        #expect(monitor.isRunning)
        #expect(monitor.isSuspended == false)
        monitor.stop()
    }

    @Test("Low Power Mode stretches the interval the loop sleeps for")
    @MainActor
    func lowPowerModeStretchesTheInterval() {
        let monitor = SystemMonitor(interval: 1.5)
        let expected = ProcessInfo.processInfo.isLowPowerModeEnabled
            ? 1.5 * SystemMonitor.lowPowerMultiplier
            : 1.5

        #expect(monitor.effectiveInterval == expected)
        #expect(monitor.effectiveInterval >= monitor.interval)
    }
}
