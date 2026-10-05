import Testing
@testable import GlassDeckKit

@Suite("Memory pressure")
struct MemoryPressureTests {
    @Test("The kernel's pressure levels map to normal, warning and critical", arguments: [
        (Int32(1), MemoryPressure.normal),
        (Int32(2), MemoryPressure.warning),
        (Int32(4), MemoryPressure.critical),
    ])
    func kernelLevels(level: Int32, expected: MemoryPressure) {
        #expect(MemoryPressure(kernelLevel: level) == expected)
    }

    @Test("An unknown kernel level reads as normal rather than as an alarm")
    func unknownLevel() {
        #expect(MemoryPressure(kernelLevel: 0) == .normal)
        #expect(MemoryPressure(kernelLevel: 99) == .normal)
    }

    @Test("Pressure is what the kernel says is not available, when it says")
    func pressureFromKernel() {
        let memory = MemoryUsage(total: 8_000, wired: 1_000, compressed: 1_000, availableFraction: 0.52)
        #expect(abs(memory.pressure - 0.48) < 0.000_001)
    }

    @Test("A full RAM at normal pressure is not trouble; the kernel's level is")
    func strain() {
        let full = MemoryUsage(total: 8_000, appMemory: 7_000, wired: 500, compressed: 400, availableFraction: 0.5)
        #expect(full.usedFraction > 0.9)
        #expect(full.strain < 0.7)

        var warning = full
        warning.pressureLevel = .warning
        #expect(warning.strain >= 0.7 && warning.strain < 0.88)

        var critical = full
        critical.pressureLevel = .critical
        #expect(critical.strain >= 0.88)
    }

    @Test("Only memory swaps its fill for its strain")
    func snapshotStrain() {
        var snapshot = MetricsSnapshot.empty
        snapshot.memory = MemoryUsage(total: 8_000, appMemory: 7_500, availableFraction: 0.6)
        snapshot.cpu = CPUUsage(perCore: [0.95])
        #expect(snapshot.strain(for: .memory) < 0.7)
        #expect(snapshot.strain(for: .cpu) == snapshot.fraction(for: .cpu))
    }

    @Test("Swap is reported against the swap there is")
    func swapFraction() {
        #expect(MemoryUsage(swapUsed: 256, swapTotal: 1_024).swapFraction == 0.25)
        #expect(MemoryUsage.zero.swapFraction == 0)
    }

    @Test("The memory details carry the pressure and the swap")
    func details() {
        var snapshot = MetricsSnapshot.empty
        snapshot.memory = MemoryUsage(total: 8_000, availableFraction: 0.5, pressureLevel: .warning)
        let labels = snapshot.details(for: .memory).map(\.label)
        #expect(labels.contains("pressure"))
        #expect(labels.contains("swap"))
    }
}
