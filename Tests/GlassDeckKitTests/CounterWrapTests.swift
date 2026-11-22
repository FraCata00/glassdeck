import Foundation
import Testing
@testable import GlassDeckKit

/// The kernel's network byte counters are 32-bit and wrap every 4 GiB. Before
/// these, the wrap widened into a delta of ~1.8e19, which pinned the gauge and —
/// at the 0.5 s cadence the settings slider allows — trapped in `UInt64(_:)`.
@Suite("Counter wraparound")
struct CounterWrapTests {
    private typealias Counters = NetworkSampler.Counters

    @Test("A wrapped 32-bit counter yields the bytes that actually moved")
    func wrapProducesTheRealDelta() {
        // 1 KB moved across the 2^32 boundary: 512 bytes before it, 512 after.
        let before = ["en0": Counters(received: UInt32.max - 511, sent: 0)]
        let after = ["en0": Counters(received: 512, sent: 0)]

        let moved = NetworkSampler.bytesMoved(from: before, to: after)
        #expect(moved.received == 1024)
    }

    @Test("Deltas are summed per interface, not across a shared total")
    func perInterfaceDeltas() {
        let before = ["en0": Counters(received: 1_000, sent: 10), "en1": Counters(received: 4_000_000_000, sent: 20)]
        let after = ["en0": Counters(received: 3_000, sent: 40), "en1": Counters(received: 4_000_001_000, sent: 25)]

        let moved = NetworkSampler.bytesMoved(from: before, to: after)
        #expect(moved.received == 3_000)
        #expect(moved.sent == 35)
    }

    @Test("An interface that appears mid-session contributes nothing yet")
    func newInterfaceHasNoDelta() {
        let before = ["en0": Counters(received: 1_000, sent: 0)]
        let after = ["en0": Counters(received: 1_500, sent: 0), "utun9": Counters(received: 900_000, sent: 0)]

        let moved = NetworkSampler.bytesMoved(from: before, to: after)
        #expect(moved.received == 500)
    }

    @Test("An interface that disappears does not drag the total negative")
    func removedInterfaceIsIgnored() {
        let before = ["en0": Counters(received: 1_000, sent: 0), "en5": Counters(received: 8_000_000, sent: 0)]
        let after = ["en0": Counters(received: 1_200, sent: 0)]

        let moved = NetworkSampler.bytesMoved(from: before, to: after)
        #expect(moved.received == 200)
    }

    @Test("Rates saturate instead of trapping on an out-of-range reading")
    func rateSaturates() {
        // What a wrapped delta divided by a 0.5 s interval used to produce.
        #expect(ValueFormatter.rate(3.6893488138859102e19).hasSuffix("/s"))
        #expect(ValueFormatter.rate(Double(UInt64.max)).hasSuffix("/s"))
        #expect(ValueFormatter.rate(Double.greatestFiniteMagnitude).hasSuffix("/s"))
        #expect(ValueFormatter.rate(-5) == "0 B/s")
        #expect(ValueFormatter.rate(.infinity) == "0 B/s")
        #expect(ValueFormatter.rate(.nan) == "0 B/s")
    }

    @Test("Ejecting a disk does not hide what the others did in that tick")
    func diskRemovalKeepsTheOtherDisks() {
        typealias Disk = DiskSampler.IOCounters
        // The internal SSD reads 4 MB while an external drive with 900 GB of
        // history goes away. A grand total fell, and the tick read as nothing.
        let before: [UInt64: Disk] = [1: Disk(read: 10_000_000, written: 0), 2: Disk(read: 900_000_000_000, written: 5)]
        let after: [UInt64: Disk] = [1: Disk(read: 14_000_000, written: 0)]
        #expect(DiskSampler.bytesMoved(from: before, to: after) == Disk(read: 4_000_000, written: 0))

        // A disk that has just appeared has no delta yet, whatever its history.
        let attached: [UInt64: Disk] = [1: Disk(read: 14_000_000, written: 0), 3: Disk(read: 2_000_000_000, written: 7)]
        #expect(DiskSampler.bytesMoved(from: after, to: attached) == Disk())

        // A counter that went backwards is a reset, not a wrap into exabytes.
        let reset: [UInt64: Disk] = [1: Disk(read: 100, written: 0)]
        #expect(DiskSampler.bytesMoved(from: after, to: reset) == Disk())
    }
}
