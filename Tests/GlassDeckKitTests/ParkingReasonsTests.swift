import Testing
import GlassDeckKit

@Suite("Parking reasons")
struct ParkingReasonsTests {
    @Test("A wake does not resume sampling while another user is in front")
    func sessionHoldsThroughAWake() {
        var reasons: ParkingReasons = [.sessionInactive]
        reasons.insert(.screensAsleep)
        reasons.remove(.screensAsleep)
        #expect(reasons.isParked)
        reasons.insert(.systemAsleep)
        reasons.systemDidWake()
        #expect(reasons.isParked)
        reasons.remove(.sessionInactive)
        #expect(!reasons.isParked)
    }

    @Test("Coming out of system sleep clears a screens' sleep left behind")
    func systemWakeClearsScreens() {
        var reasons: ParkingReasons = [.screensAsleep, .systemAsleep]
        reasons.systemDidWake()
        #expect(!reasons.isParked)
    }
}
