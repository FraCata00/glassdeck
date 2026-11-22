import Foundation
import Testing
@testable import GlassDeckKit

/// The fans, the thermometers, the wattage and the Bluetooth batteries all hold
/// a reading for a few seconds through the same cache.
@Suite("Reading cache")
struct ReadingCacheTests {
    @Test("A reading stands for the interval, then the source is asked again")
    func standsForTheInterval() {
        var cache = ReadingCache<Int>(interval: 5)
        var reads = 0
        let start = Date()

        for offset in [0, 1.5, 4.99] {
            #expect(cache.value(at: start.addingTimeInterval(offset)) { reads += 1; return reads } == 1)
        }
        #expect(cache.value(at: start.addingTimeInterval(5)) { reads += 1; return reads } == 2)
    }

    @Test("A wall clock stepping backwards does not freeze the reading")
    func clockSteppingBackIsStale() {
        // Before, an hour's step back left the age at -3600 s — "fresh" — and
        // the sensors were not read again until the clock had caught up.
        var cache = ReadingCache<Int>(interval: 5)
        var reads = 0
        let start = Date()

        _ = cache.value(at: start) { reads += 1; return reads }
        #expect(cache.value(at: start.addingTimeInterval(-3600)) { reads += 1; return reads } == 2)
        // And the new reading then stands from the corrected time.
        #expect(cache.value(at: start.addingTimeInterval(-3598)) { reads += 1; return reads } == 2)
    }

    @Test("The thermometers are read again after the clock steps back")
    func thermalSamplerFollowsTheClockBack() {
        let sampler = ThermalSampler(smc: nil, catalogue: SensorCatalogue(smc: nil), refreshInterval: 5)
        let start = Date()

        _ = sampler.sample(at: start)
        _ = sampler.sample(at: start.addingTimeInterval(-60))
        #expect(sampler.readCount == 2)
    }

    @Test("The Bluetooth stack is asked again after the clock steps back")
    func bluetoothFollowsTheClockBack() {
        let source = BluetoothTests.StubSource([])
        let sampler = BluetoothSampler(source: source)
        let start = Date()

        _ = sampler.sample(at: start)
        _ = sampler.sample(at: start.addingTimeInterval(1))
        #expect(source.reads == 1)
        _ = sampler.sample(at: start.addingTimeInterval(-60))
        #expect(source.reads == 2)
    }
}
