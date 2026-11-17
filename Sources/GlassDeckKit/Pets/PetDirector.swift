import Foundation

/// Decides when the pet comes and goes. Fed once per sample, it answers with
/// what the bar should do; it never keeps time of its own, so a parked bar
/// simply stops asking.
///
/// Visits are rare by design — a gap drawn afresh after each one, so they are
/// not predictable — but a reading that jumps into a notable mood brings the
/// pet at once, at most once per cooldown so a busy machine does not turn it
/// into an alarm.
public struct PetDirector: Sendable {
    public struct Configuration: Sendable, Equatable {
        /// Seconds between the end of one visit and the next random one.
        public var visitGap: ClosedRange<TimeInterval>
        /// Seconds after a spike visit before another spike may bring the pet.
        public var spikeCooldown: TimeInterval
        /// How often opening a metric's detail finds the pet in it.
        public var detailChance: Double

        public init(
            visitGap: ClosedRange<TimeInterval> = 480...1500,
            spikeCooldown: TimeInterval = 300,
            detailChance: Double = 0.25
        ) {
            self.visitGap = visitGap
            self.spikeCooldown = spikeCooldown
            self.detailChance = detailChance
        }
    }

    public enum Phase: Equatable, Sendable {
        case away
        /// Walking across; the crossing is over at `until`.
        case crossing(until: Date)
        /// Stopped at the far end because the spike is still going on.
        case lingering
    }

    public enum Action: Equatable, Sendable {
        case none
        /// Set off across the bar; the crossing lasts this many seconds.
        case enter(duration: TimeInterval)
        /// Stay at the far end and act out the mood: returned on every sample
        /// for as long as the spike lasts.
        case linger
        /// Walk off the far edge.
        case leave
    }

    public let configuration: Configuration
    public private(set) var phase: Phase = .away
    public private(set) var nextVisit: Date
    private var lastSpikeVisit: Date?
    private var previousMood: PetMood = .calm

    public init(
        now: Date,
        configuration: Configuration = Configuration(),
        random: inout some RandomNumberGenerator
    ) {
        self.configuration = configuration
        nextVisit = now.addingTimeInterval(TimeInterval.random(in: configuration.visitGap, using: &random))
    }

    public mutating func step(
        mood: PetMood,
        at now: Date,
        random: inout some RandomNumberGenerator
    ) -> Action {
        // A rising edge only: a machine that stays busy brought the pet once.
        let spikeBegan = mood.isSpike && mood != previousMood
        previousMood = mood

        switch phase {
        case .away:
            let cooledDown = lastSpikeVisit.map { now.timeIntervalSince($0) >= configuration.spikeCooldown } ?? true
            if spikeBegan, cooledDown {
                lastSpikeVisit = now
                return enter(mood: mood, at: now)
            }
            guard now >= nextVisit else { return .none }
            return enter(mood: mood, at: now)
        case let .crossing(until):
            guard now >= until else { return .none }
            fallthrough
        case .lingering:
            if mood.isSpike {
                phase = .lingering
                return .linger
            }
            finish(at: now, random: &random)
            return .leave
        }
    }

    /// Ends a visit cut short — the bar changed size or went away — and puts
    /// the next one a full gap away, as if it had ended normally.
    public mutating func interrupt(at now: Date, random: inout some RandomNumberGenerator) {
        guard phase != .away else { return }
        finish(at: now, random: &random)
    }

    /// Brings the pet on the next sample. For testing by hand.
    public mutating func summon(at now: Date) {
        nextVisit = now
    }

    /// Whether this opening of a metric's detail finds the pet in it.
    public func showsInDetail(random: inout some RandomNumberGenerator) -> Bool {
        Double.random(in: 0..<1, using: &random) < configuration.detailChance
    }

    private mutating func enter(mood: PetMood, at now: Date) -> Action {
        let duration = mood.crossingDuration
        phase = .crossing(until: now.addingTimeInterval(duration))
        return .enter(duration: duration)
    }

    private mutating func finish(at now: Date, random: inout some RandomNumberGenerator) {
        phase = .away
        nextVisit = now.addingTimeInterval(TimeInterval.random(in: configuration.visitGap, using: &random))
    }
}
