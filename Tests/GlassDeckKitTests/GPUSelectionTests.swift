import Foundation
import Testing
@testable import GlassDeckKit

/// A Mac with more than one accelerator used to have the reported GPU — name
/// and number both — jump between devices on every sample, because the busiest
/// was re-picked from scratch each time.
@Suite("GPU device selection")
struct GPUSelectionTests {
    private typealias Accelerator = GPUSampler.Accelerator

    private func gpu(_ name: String, _ utilisation: Double) -> GPUUsage {
        GPUUsage(name: name, utilisation: utilisation, isAvailable: true)
    }

    private var pair: [Accelerator] {
        [
            Accelerator(id: 1, usage: gpu("Integrated", 0.30)),
            Accelerator(id: 2, usage: gpu("Discrete", 0.32)),
        ]
    }

    @Test("The first sample takes the busiest accelerator")
    func firstSampleTakesTheBusiest() {
        #expect(GPUSampler.select(from: pair, following: nil)?.id == 2)
    }

    @Test("A device stays put while another is busier only within the margin")
    func noiseDoesNotHandOver() {
        // Integrated is followed and 2 points behind: not enough to lose it.
        #expect(GPUSampler.select(from: pair, following: 1)?.id == 1)
    }

    @Test("A clearly busier accelerator takes the reading over")
    func realLoadHandsOver() {
        let underLoad = [
            Accelerator(id: 1, usage: gpu("Integrated", 0.05)),
            Accelerator(id: 2, usage: gpu("Discrete", 0.90)),
        ]
        #expect(GPUSampler.select(from: underLoad, following: 1)?.id == 2)
    }

    @Test("The margin is the boundary, not an approximation")
    func marginBoundary() {
        let atMargin = [
            Accelerator(id: 1, usage: gpu("Integrated", 0.20)),
            Accelerator(id: 2, usage: gpu("Discrete", 0.20 + GPUSampler.handoverMargin)),
        ]
        // Exactly at the margin is not "clearly busier": the followed device keeps it.
        #expect(GPUSampler.select(from: atMargin, following: 1)?.id == 1)
    }

    @Test("A device that goes away falls back to the busiest that remains")
    func unpluggedDeviceFallsBack() {
        let remaining = [Accelerator(id: 2, usage: gpu("Discrete", 0.10))]
        #expect(GPUSampler.select(from: remaining, following: 1)?.id == 2)
    }

    @Test("No accelerators at all reports nothing rather than a stale device")
    func noAccelerators() {
        #expect(GPUSampler.select(from: [], following: 1) == nil)
    }
}
