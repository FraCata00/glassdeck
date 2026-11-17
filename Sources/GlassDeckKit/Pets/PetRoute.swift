import Foundation

/// A crossing worked out in advance: walks broken by the odd pause and hop, so
/// the pet looks as if it were making up its mind on the way.
///
/// It is computed once, when the pet sets off, and played as a single finite
/// animation — the pauses and hops cost nothing extra, because nothing has to
/// wake up to start them.
public struct PetRoute: Sendable, Equatable {
    public enum Move: Sendable, Equatable {
        case walk
        /// Standing still, with a blink halfway through.
        case pause
        /// A jump on the spot.
        case hop
    }

    public struct Segment: Sendable, Equatable {
        public var move: Move
        public var start: TimeInterval
        public var end: TimeInterval
        public var fromX: Double
        public var toX: Double
    }

    public let segments: [Segment]

    public var duration: TimeInterval { segments.last?.end ?? 0 }

    /// How long a hop lasts, and how high it goes in points.
    public static let hopDuration: TimeInterval = 0.45
    public static let hopHeight: Double = 7
    /// How long a blink keeps the eyes shut.
    static let blinkDuration: TimeInterval = 0.18

    public init(segments: [Segment]) {
        self.segments = segments
    }

    /// A crossing from `startX` to `endX` lasting `duration` seconds.
    ///
    /// The stops sit somewhere in the middle three fifths of the way, so the
    /// pet is well on the bar when it stops and does not dawdle at the edges.
    /// What the stops are depends on the mood: a busy pet hops but never stops,
    /// a tired one stops twice and long.
    public static func crossing(
        from startX: Double,
        to endX: Double,
        duration: TimeInterval,
        mood: PetMood,
        random: inout some RandomNumberGenerator
    ) -> PetRoute {
        let stops: [(move: Move, length: TimeInterval)] = switch mood {
        case .busy: [(.hop, hopDuration), (.hop, hopDuration)]
        case .drained, .sleepy: [
            (.pause, TimeInterval.random(in: 2...3.5, using: &random)),
            (.pause, TimeInterval.random(in: 2...3.5, using: &random)),
        ]
        case .hot: [(.pause, TimeInterval.random(in: 1.5...2.5, using: &random))]
        case .calm, .carrying, .charging, .squeezed: [
            (.pause, TimeInterval.random(in: 1.2...2.4, using: &random)),
            (.hop, hopDuration),
        ].shuffled(using: &random)
        }

        let stopTime = stops.reduce(0) { $0 + $1.length }
        // Never let the stops eat the walk: on a short crossing they shrink.
        let scale = min(1, (duration * 0.5) / max(stopTime, .ulpOfOne))
        let walkTime = duration - stopTime * scale
        let distance = endX - startX
        let fractions = stops.map { _ in Double.random(in: 0.2...0.8, using: &random) }.sorted()

        var segments: [Segment] = []
        var time: TimeInterval = 0
        var x = startX
        for (stop, fraction) in zip(stops, fractions) {
            let stopX = startX + distance * fraction
            let walk = walkTime * abs(stopX - x) / max(abs(distance), .ulpOfOne)
            segments.append(Segment(move: .walk, start: time, end: time + walk, fromX: x, toX: stopX))
            time += walk
            x = stopX
            let length = stop.length * scale
            segments.append(Segment(move: stop.move, start: time, end: time + length, fromX: x, toX: x))
            time += length
        }
        segments.append(Segment(move: .walk, start: time, end: duration, fromX: x, toX: endX))
        return PetRoute(segments: segments.filter { $0.end > $0.start })
    }

    public func x(at time: TimeInterval) -> Double {
        guard let segment = segment(at: time) else { return segments.last?.toX ?? 0 }
        let progress = (time - segment.start) / (segment.end - segment.start)
        return segment.fromX + (segment.toX - segment.fromX) * progress
    }

    /// The pose at `time`: the walk alternates its two frames every
    /// `stepInterval`, a pause stands and blinks once, a hop is in the air.
    public func pose(at time: TimeInterval, stepInterval: TimeInterval) -> PetArt.Pose {
        guard let segment = segment(at: time) else { return .stand }
        switch segment.move {
        case .walk:
            let step = Int(((time - segment.start) / stepInterval).rounded(.down))
            return step.isMultiple(of: 2) ? .stand : .step
        case .pause:
            let middle = (segment.start + segment.end) / 2
            return (middle..<middle + Self.blinkDuration).contains(time) ? .blink : .stand
        case .hop:
            return .jump
        }
    }

    /// Every change of pose from `time` to the end, as times measured from
    /// `time`: what a discrete keyframe animation of the frames needs. Starting
    /// part-way lets the frames be replaced when the mood changes mid-crossing.
    public func poseChanges(from time: TimeInterval, stepInterval: TimeInterval) -> [(time: TimeInterval, pose: PetArt.Pose)] {
        var instants: Set<TimeInterval> = [time]
        for segment in segments where segment.end > time {
            switch segment.move {
            case .walk:
                var t = segment.start
                while t < segment.end {
                    if t >= time { instants.insert(t) }
                    t += stepInterval
                }
            case .pause:
                let middle = (segment.start + segment.end) / 2
                for t in [segment.start, middle, middle + Self.blinkDuration] where t >= time && t < segment.end {
                    instants.insert(t)
                }
            case .hop:
                if segment.start >= time { instants.insert(segment.start) }
            }
        }
        var changes: [(time: TimeInterval, pose: PetArt.Pose)] = []
        for instant in instants.sorted() {
            let pose = pose(at: instant, stepInterval: stepInterval)
            if changes.last?.pose != pose { changes.append((instant - time, pose)) }
        }
        return changes
    }

    private func segment(at time: TimeInterval) -> Segment? {
        segments.first { time >= $0.start && time < $0.end }
    }
}

/// What the pet does when it is not crossing — sitting in a metric's detail,
/// or waiting at the end of the bar for a spike to pass. Asked once a sample,
/// it picks the next little thing to do.
///
/// The choice leans on the mood: a busy pet paces and hops and never sleeps, a
/// hot one hardly moves, a sleepy machine has a sleeping pet. A calm pet that
/// has been awake for a while may doze off for a few samples and wake again,
/// which is most of what makes it look alive rather than looped.
public struct PetBehaviour: Sendable {
    public enum Activity: Sendable, Equatable {
        case stand
        case blink
        /// Walk this many points; negative is towards the leading edge.
        case walk(by: Double)
        case hop
        /// Turn round where it stands.
        case turn
        case sleep
    }

    /// How far from its spot the pet may wander, in points.
    public let range: ClosedRange<Double>
    public private(set) var offset: Double = 0
    public private(set) var facesLeading = false
    public private(set) var isAsleep = false
    private var awakeSamples = 0
    private var sleepSamplesLeft = 0

    /// Samples awake before a calm pet may doze off.
    static let wakefulness = 8

    public init(range: ClosedRange<Double>) {
        self.range = range
    }

    public mutating func next(mood: PetMood, random: inout some RandomNumberGenerator) -> Activity {
        if mood == .sleepy {
            isAsleep = true
            return .sleep
        }
        if isAsleep {
            // Load wakes a pet at once; otherwise it sleeps its nap out.
            if mood.isSpike || sleepSamplesLeft <= 0 {
                isAsleep = false
                awakeSamples = 0
                return .hop
            }
            sleepSamplesLeft -= 1
            return .sleep
        }
        awakeSamples += 1

        let weights: [(Activity, Double)] = switch mood {
        case .busy: [(.walk(by: 0), 4), (.hop, 3), (.stand, 1.5), (.turn, 1)]
        case .hot, .squeezed: [(.stand, 6), (.blink, 2), (.walk(by: 0), 1.5), (.turn, 0.5)]
        case .drained: [(.stand, 4), (.blink, 2), (.walk(by: 0), 1), (.sleep, 3)]
        case .calm, .carrying, .charging, .sleepy: [
            (.stand, 3.5), (.blink, 2), (.walk(by: 0), 2.5), (.hop, 1), (.turn, 1), (.sleep, 1),
        ]
        }
        let candidates = weights.filter { activity, _ in
            activity != .sleep || awakeSamples >= Self.wakefulness
        }
        let total = candidates.reduce(0) { $0 + $1.1 }
        var pick = Double.random(in: 0..<total, using: &random)
        var activity = candidates.last!.0
        for (candidate, weight) in candidates {
            if pick < weight { activity = candidate; break }
            pick -= weight
        }

        switch activity {
        case .walk:
            return walk(mood: mood, random: &random)
        case .turn:
            facesLeading.toggle()
            return .turn
        case .sleep:
            isAsleep = true
            sleepSamplesLeft = Int.random(in: 5...12, using: &random)
            return .sleep
        case .stand, .blink, .hop:
            return activity
        }
    }

    /// Woken by a tap: up at once, with the full stretch awake before the
    /// next nap.
    public mutating func wake() {
        isAsleep = false
        awakeSamples = 0
        sleepSamplesLeft = 0
    }

    /// A few steps, usually the way it faces; at the edge of its range it
    /// turns back rather than walking into the readings.
    private mutating func walk(mood: PetMood, random: inout some RandomNumberGenerator) -> Activity {
        let length = Double.random(in: mood == .busy ? 10...22 : 6...16, using: &random)
        var leading = Double.random(in: 0..<1, using: &random) < 0.75 ? facesLeading : !facesLeading
        if leading, offset - length < range.lowerBound { leading = false }
        if !leading, offset + length > range.upperBound { leading = true }
        let target = min(max(offset + (leading ? -length : length), range.lowerBound), range.upperBound)
        let distance = target - offset
        guard abs(distance) >= 1 else { return .stand }
        offset = target
        facesLeading = distance < 0
        return .walk(by: distance)
    }
}
