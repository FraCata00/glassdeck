import Foundation
import Testing
@testable import GlassDeckKit

@Suite("Peak tracking")
struct PeakTrackerTests {
    @Test("A fresh tracker sits at its floor")
    func startsAtFloor() {
        var tracker = PeakTracker(floor: 100)
        #expect(tracker.peak == 100)
        #expect(tracker.observe(10) == 100)
    }

    @Test("A new high becomes the scale immediately")
    func risesAtOnce() {
        var tracker = PeakTracker(floor: 100)
        #expect(tracker.observe(1_000) == 1_000)
    }

    @Test("A peak fades rather than standing for the session")
    func decays() {
        var tracker = PeakTracker(floor: 100, decay: 0.9)
        tracker.observe(1_000)
        for _ in 0..<10 { tracker.observe(0) }
        #expect(tracker.peak < 1_000)
        #expect(tracker.peak > 100)          // but not all the way back at once
    }

    @Test("Fading stops at the floor")
    func neverBelowFloor() {
        var tracker = PeakTracker(floor: 100, decay: 0.5)
        tracker.observe(1_000)
        for _ in 0..<50 { tracker.observe(0) }
        #expect(tracker.peak == 100)
    }

    @Test("A nonsense reading is ignored rather than becoming the scale")
    func rejectsBadInput() {
        var tracker = PeakTracker(floor: 100)
        tracker.observe(500)
        let peak = tracker.peak
        #expect(tracker.observe(.nan) == peak)
        #expect(tracker.observe(.infinity) == peak)
        #expect(tracker.observe(-5) == peak)
    }
}
