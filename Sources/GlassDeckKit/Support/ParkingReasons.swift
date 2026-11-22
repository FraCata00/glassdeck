/// Why sampling is parked: the reasons are tracked apart so one coming to an
/// end does not resume the loop while another still holds.
///
/// A single flag let any wake event resume. With another user switched in
/// front, the screens waking or the machine coming out of sleep restarted
/// sampling for a session nobody could see, and it then ran until the user
/// came back.
public struct ParkingReasons: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// The displays are asleep.
    public static let screensAsleep = ParkingReasons(rawValue: 1 << 0)
    /// The machine is going to sleep, or has.
    public static let systemAsleep = ParkingReasons(rawValue: 1 << 1)
    /// Another user's session is in front.
    public static let sessionInactive = ParkingReasons(rawValue: 1 << 2)

    /// Whether sampling should be parked for the reasons held.
    public var isParked: Bool { !isEmpty }

    /// Coming out of system sleep also clears the screens' sleep: the screens'
    /// own wake is not always sent after a dark wake, and the loop must never
    /// stay parked on a reason that has quietly gone away. Leaving it running
    /// for a dark screen costs no more than it did before.
    public mutating func systemDidWake() {
        subtract([.systemAsleep, .screensAsleep])
    }
}
