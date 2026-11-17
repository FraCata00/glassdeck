import Foundation

/// What the pet acts out, read from the machine.
///
/// Declared in priority order: when several apply, the first one wins. A
/// battery about to run out matters more than a hot one, and heat more than
/// load, because each is the likelier cause of the next.
public enum PetMood: Int, Sendable, CaseIterable, Comparable {
    case drained
    case hot
    case squeezed
    case busy
    case carrying
    case charging
    case sleepy
    case calm

    public static func < (lhs: PetMood, rhs: PetMood) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The moods worth an unscheduled visit: something the owner would want to
    /// notice. Network traffic and charging are pleasant, not notable.
    public var isSpike: Bool {
        switch self {
        case .drained, .hot, .squeezed, .busy: true
        case .carrying, .charging, .sleepy, .calm: false
        }
    }

    /// How long one frame of the walk is held, in seconds. Busy runs, a drained
    /// battery drags.
    public var stepInterval: TimeInterval {
        switch self {
        case .busy: 0.16
        case .drained, .sleepy: 0.55
        case .hot, .squeezed, .carrying, .charging, .calm: 0.3
        }
    }

    /// How fast the pet walks when it is not crossing, in art pixels a
    /// second: about three pixels a step, so the walk cycle sets the pace.
    public var walkSpeed: Double { 3 / stepInterval }

    /// How long a crossing takes when the pet sets off in this mood. Fixed for
    /// the whole crossing: changing speed halfway would mean replacing the
    /// movement, and the walk cycle already says how it feels.
    public var crossingDuration: TimeInterval {
        switch self {
        case .busy: 14
        case .drained: 34
        case .sleepy: 30
        case .hot, .squeezed, .carrying, .charging, .calm: 24
        }
    }

    /// The mood the pet shows in a metric's detail: only what that metric is
    /// saying, so in the temperature detail it is hot or calm, never busy.
    public static func forDetail(_ kind: MetricKind, in snapshot: MetricsSnapshot) -> PetMood {
        switch kind {
        case .cpu, .gpu, .disk, .power:
            StrainBand(strain: snapshot.strain(for: kind)) == .high ? .busy : .calm
        case .memory:
            snapshot.memory.pressureLevel == .critical ? .squeezed : .calm
        case .network:
            snapshot.network.loadFraction >= PetMoodResolver.carryingEnter ? .carrying : .calm
        case .temperature, .fans:
            PetMoodResolver.isHot(snapshot, wasHot: false) ? .hot : .calm
        case .battery:
            if PetMoodResolver.isDrained(snapshot.battery, wasDrained: false) { .drained }
            else if snapshot.battery.isAvailable, snapshot.battery.isCharging { .charging }
            else { .calm }
        }
    }
}

/// Turns successive snapshots into a mood, with hysteresis so a reading sitting
/// on a threshold does not make the pet flicker between two moods.
///
/// Each condition has a level to enter at and a lower one to leave at; once
/// active it stays so until the reading falls past the second. Load uses the
/// status colours' bands — busy from high, back from calm — so the pet and the
/// bar's signal style never disagree about a reading.
public struct PetMoodResolver: Sendable {
    /// Degrees Celsius: past 90 a Mac is close to throttling, and the hottest
    /// sensor is what the temperature gauge already shows. Deliberately not
    /// the alert threshold in settings: that one is the owner's to lower for
    /// an early warning, and a pet sweating at 70 °C would be crying wolf.
    static let hotEnter = 90.0
    static let hotExit = 85.0
    static let fansEnter = 0.9
    static let fansExit = 0.8
    static let drainedEnter = 0.10
    static let drainedExit = 0.12
    static let carryingEnter = 0.6
    static let carryingExit = 0.4
    static let idleEnter = 0.05
    static let idleExit = 0.10
    /// How long the CPU has to stay idle before the pet dozes off: long enough
    /// that a pause between two tasks does not count.
    static let sleepAfter: TimeInterval = 180

    private var active: Set<PetMood> = []
    private var idleSince: Date?

    public private(set) var mood: PetMood = .calm

    public init() {}

    @discardableResult
    public mutating func update(with snapshot: MetricsSnapshot) -> PetMood {
        var next: Set<PetMood> = []
        if Self.isDrained(snapshot.battery, wasDrained: active.contains(.drained)) { next.insert(.drained) }
        if Self.isHot(snapshot, wasHot: active.contains(.hot)) { next.insert(.hot) }
        if snapshot.memory.pressureLevel == .critical { next.insert(.squeezed) }

        let cpu = snapshot.cpu.total
        let load = StrainBand(strain: snapshot.strain(for: .cpu))
        if active.contains(.busy) ? load != .calm : load == .high { next.insert(.busy) }

        let traffic = snapshot.network.loadFraction
        if traffic >= (active.contains(.carrying) ? Self.carryingExit : Self.carryingEnter) { next.insert(.carrying) }

        if snapshot.battery.isAvailable, snapshot.battery.isCharging { next.insert(.charging) }

        if cpu < (idleSince == nil ? Self.idleEnter : Self.idleExit) {
            let since = idleSince ?? snapshot.timestamp
            idleSince = since
            if snapshot.timestamp.timeIntervalSince(since) >= Self.sleepAfter { next.insert(.sleepy) }
        } else {
            idleSince = nil
        }

        active = next
        mood = next.min() ?? .calm
        return mood
    }

    /// A battery that is low *and* running down. Plugged in, a low charge is
    /// on its way up and nothing to worry about.
    static func isDrained(_ battery: BatteryUsage, wasDrained: Bool) -> Bool {
        guard battery.isAvailable, !battery.isPluggedIn else { return false }
        return battery.fraction < (wasDrained ? drainedExit : drainedEnter)
    }

    /// Hot by temperature or by fans near their maximum: a Mac whose sensors
    /// cannot be read still says it is struggling through its fans.
    static func isHot(_ snapshot: MetricsSnapshot, wasHot: Bool) -> Bool {
        if snapshot.thermal.isAvailable, let hottest = snapshot.thermal.hottest,
           hottest >= (wasHot ? hotExit : hotEnter) {
            return true
        }
        if snapshot.fans.isAvailable,
           snapshot.fans.loadFraction >= (wasHot ? fansExit : fansEnter) {
            return true
        }
        return false
    }
}
