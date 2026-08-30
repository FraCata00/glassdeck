import Testing
@testable import GlassDeckKit

@Suite("Metric models")
struct MetricsModelTests {
    @Test("Memory used is app memory plus wired plus compressed, as Activity Monitor counts it")
    func memoryUsed() {
        let memory = MemoryUsage(
            total: 8_000,
            appMemory: 2_000,
            active: 3_500,
            wired: 1_000,
            compressed: 1_000,
            inactive: 3_000,
            free: 1_000
        )
        // `active` is larger than app memory here on purpose: it counts evictable
        // file-backed pages, and using it would report 5,500 as used.
        #expect(memory.used == 4_000)
        #expect(memory.usedFraction == 0.5)
        #expect(memory.pressure == 0.25)
    }

    @Test("A zero-capacity volume reports no usage instead of dividing by zero")
    func emptyDisk() {
        #expect(DiskUsage.zero.usedFraction == 0)
        #expect(DiskUsage.zero.used == 0)
    }

    @Test("CPU clusters are only reported when the core counts add up")
    func cpuClusters() {
        let apple = CPUUsage(
            perCore: [0.8, 0.6, 0.4, 0.2, 0.1, 0.1, 0.1, 0.1],
            performanceCoreCount: 4,
            efficiencyCoreCount: 4
        )
        // Means of binary fractions do not land on exact decimals.
        #expect(abs((apple.performanceClusterLoad ?? 0) - 0.5) < 0.000_001)
        #expect(abs((apple.efficiencyClusterLoad ?? 0) - 0.1) < 0.000_001)

        // Intel Macs report no cluster topology at all.
        let intel = CPUUsage(perCore: [0.5, 0.5])
        #expect(intel.performanceClusterLoad == nil)
        #expect(intel.efficiencyClusterLoad == nil)
    }

    @Test("Busy fraction is everything that is not idle")
    func cpuTotal() {
        let cpu = CPUUsage(user: 0.3, system: 0.15, nice: 0.05, idle: 0.5)
        #expect(abs(cpu.total - 0.5) < 0.000_001)
    }

    @Test("A stopped fan reads as idle rather than as its minimum speed")
    func fanIdle() {
        let stopped = Fan(index: 0, rpm: 0, minimumRPM: 1_200, maximumRPM: 7_200)
        #expect(stopped.fraction == 0)

        let spinning = Fan(index: 0, rpm: 4_200, minimumRPM: 1_200, maximumRPM: 7_200)
        #expect(abs(spinning.fraction - 0.5) < 0.000_001)

        let usage = FanUsage(fans: [stopped, spinning], isAvailable: true)
        #expect(usage.topRPM == 4_200)
        #expect(usage.headline == "4200 rpm")
    }

    @Test("Fanless and battery-less Macs are reported as unsupported, not as zero")
    func unsupportedHardware() {
        let snapshot = MetricsSnapshot()
        #expect(snapshot.supports(.cpu))
        #expect(!snapshot.supports(.fans))
        #expect(!snapshot.supports(.battery))
        #expect(snapshot.headline(for: .fans) == "n/a")
        #expect(FanUsage.unavailable.caption == "fanless Mac")
    }

    @Test("Battery glyph follows the charge level and the charging state")
    func batterySymbols() {
        #expect(BatteryUsage(fraction: 0.95, isAvailable: true).symbolName == "battery.100")
        #expect(BatteryUsage(fraction: 0.05, isAvailable: true).symbolName == "battery.0")
        #expect(BatteryUsage(fraction: 0.05, isCharging: true, isAvailable: true).symbolName == "battery.100.bolt")
        #expect(BatteryUsage.unavailable.symbolName == "battery.slash")
    }

    @Test("Battery caption spells out the time estimate when the system has one")
    func batteryCaption() {
        let discharging = BatteryUsage(fraction: 0.5, minutesRemaining: 95, isAvailable: true)
        #expect(discharging.caption == "on battery · 1h 35m left")

        let charging = BatteryUsage(fraction: 0.5, isCharging: true, isPluggedIn: true, minutesRemaining: 20, isAvailable: true)
        #expect(charging.caption == "charging · 20m to full")
    }

    @Test("Temperature maps idle-to-throttling onto the gauge")
    func thermalScaling() {
        #expect(ThermalUsage(cpu: 30, isAvailable: true).fraction == 0)
        #expect(ThermalUsage(cpu: 65, isAvailable: true).fraction == 0.5)
        #expect(ThermalUsage(cpu: 110, isAvailable: true).fraction == 1)
        // The hottest sensor wins, whichever group it belongs to.
        #expect(ThermalUsage(cpu: 50, gpu: 71, battery: 32, isAvailable: true).headline == "71°C")
        #expect(ThermalUsage.unavailable.headline == "n/a")
    }

    @Test("Power is scaled against the adapter's rating when one is attached")
    func powerScaling() {
        let onCharger = PowerUsage(watts: 32.5, adapterWatts: 65, isAvailable: true)
        #expect(onCharger.fraction == 0.5)
        #expect(onCharger.headline == "33 W")
        #expect(onCharger.caption == "of a 65 W adapter")

        // No adapter reading: a 60 W stand-in keeps the gauge meaningful.
        let onBattery = PowerUsage(watts: 6, isAvailable: true)
        #expect(onBattery.referenceWatts == 60)
        #expect(onBattery.headline == "6.0 W")
    }

    @Test("Network load is scaled against a 100 Mbit reference")
    func networkScaling() {
        #expect(NetworkThroughput(downloadBytesPerSecond: 12_500_000).loadFraction == 1)
        #expect(NetworkThroughput(downloadBytesPerSecond: 6_250_000).loadFraction == 0.5)
        #expect(NetworkThroughput.zero.loadFraction == 0)
    }

    @Test("Metric identifiers are stable, because settings persist them")
    func metricIdentifiers() {
        #expect(
            MetricKind.allCases.map(\.rawValue) == [
                "cpu", "gpu", "memory", "disk", "network", "fans", "battery", "temperature", "power",
            ]
        )
        #expect(MetricKind(rawValue: "memory") == .memory)
    }
}
