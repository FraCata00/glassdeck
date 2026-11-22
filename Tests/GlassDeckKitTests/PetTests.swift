import Foundation
import Testing
@testable import GlassDeckKit

/// A deterministic generator, so the random gaps in these tests are the same
/// on every run.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private let start = Date(timeIntervalSinceReferenceDate: 0)

private func snapshot(
    at seconds: TimeInterval = 0,
    cpu: Double = 0.3,
    hottest: Double? = nil,
    fans: Double? = nil,
    pressure: MemoryPressure = .normal,
    network: Double = 0,
    battery: BatteryUsage = .unavailable
) -> MetricsSnapshot {
    MetricsSnapshot(
        timestamp: start.addingTimeInterval(seconds),
        cpu: CPUUsage(user: cpu, idle: 1 - cpu),
        memory: MemoryUsage(pressureLevel: pressure),
        network: NetworkThroughput(downloadBytesPerSecond: network * NetworkThroughput.minimumReference),
        fans: fans.map { FanUsage(fans: [Fan(index: 0, rpm: 1000 + $0 * 5000, minimumRPM: 1000, maximumRPM: 6000)], isAvailable: true) }
            ?? .unavailable,
        battery: battery,
        thermal: hottest.map { ThermalUsage(cpu: $0, sensorCount: 1, isAvailable: true) } ?? .unavailable
    )
}

@Suite("Pet moods")
struct PetMoodTests {
    @Test("Pets are stored by stable raw values")
    func rawValues() {
        // A rename here would silently swap everyone's pet for the default.
        #expect(TouchBarPet.allCases.map(\.rawValue) == ["off", "octopus", "frog", "coco"])
        for pet in TouchBarPet.allCases { #expect(!pet.title.isEmpty) }
    }

    @Test("Only the expanded and full bars host a crossing")
    func crossingModes() {
        #expect(TouchBarMode.expanded.hostsPetCrossing)
        #expect(TouchBarMode.fullscreen.hostsPetCrossing)
        #expect(!TouchBarMode.mini.hostsPetCrossing)
        #expect(!TouchBarMode.collapsed.hostsPetCrossing)
        #expect(!TouchBarMode.detail(.cpu).hostsPetCrossing)
    }

    @Test("Busy enters where the status colours turn high and leaves where they turn calm")
    func busyHysteresis() {
        var resolver = PetMoodResolver()
        #expect(resolver.update(with: snapshot(cpu: 0.87)) == .calm)
        #expect(resolver.update(with: snapshot(cpu: 0.89)) == .busy)
        #expect(resolver.update(with: snapshot(cpu: 0.75)) == .busy)
        #expect(resolver.update(with: snapshot(cpu: 0.69)) == .calm)
    }

    @Test("Heat comes from the hottest sensor or from fans near their maximum")
    func heat() {
        var resolver = PetMoodResolver()
        #expect(resolver.update(with: snapshot(hottest: 89)) == .calm)
        #expect(resolver.update(with: snapshot(hottest: 91)) == .hot)
        #expect(resolver.update(with: snapshot(hottest: 86)) == .hot)
        #expect(resolver.update(with: snapshot(hottest: 84)) == .calm)

        var fanned = PetMoodResolver()
        #expect(fanned.update(with: snapshot(fans: 0.95)) == .hot)
        #expect(fanned.update(with: snapshot(fans: 0.5)) == .calm)
    }

    @Test("A low battery is drained only while it runs down")
    func drained() {
        var resolver = PetMoodResolver()
        let low = BatteryUsage(fraction: 0.08, isAvailable: true)
        #expect(resolver.update(with: snapshot(battery: low)) == .drained)
        let charging = BatteryUsage(fraction: 0.08, isCharging: true, isPluggedIn: true, isAvailable: true)
        #expect(resolver.update(with: snapshot(battery: charging)) == .charging)
    }

    @Test("Several conditions resolve to the one with the highest priority")
    func priority() {
        var resolver = PetMoodResolver()
        let low = BatteryUsage(fraction: 0.05, isAvailable: true)
        #expect(resolver.update(with: snapshot(cpu: 0.95, hottest: 95, battery: low)) == .drained)
        #expect(resolver.update(with: snapshot(cpu: 0.95, hottest: 95)) == .hot)
        #expect(resolver.update(with: snapshot(cpu: 0.95, pressure: .critical)) == .squeezed)
        #expect(resolver.update(with: snapshot(cpu: 0.95, network: 0.9)) == .busy)
        #expect(resolver.update(with: snapshot(cpu: 0.3, network: 0.9)) == .carrying)
    }

    @Test("Absent hardware never triggers its mood")
    func absentHardware() {
        var resolver = PetMoodResolver()
        // No battery, no fans, no sensors: the defaults of the helper.
        #expect(resolver.update(with: snapshot(cpu: 0.3)) == .calm)
    }

    @Test("The pet dozes off after three idle minutes, and wakes at the first load")
    func sleepy() {
        var resolver = PetMoodResolver()
        #expect(resolver.update(with: snapshot(at: 0, cpu: 0.02)) == .calm)
        #expect(resolver.update(with: snapshot(at: 120, cpu: 0.07)) == .calm)
        #expect(resolver.update(with: snapshot(at: 180, cpu: 0.03)) == .sleepy)
        #expect(resolver.update(with: snapshot(at: 182, cpu: 0.2)) == .calm)
        // The clock starts again from the next idle sample.
        #expect(resolver.update(with: snapshot(at: 300, cpu: 0.02)) == .calm)
    }

    @Test("A clock set back does not keep the pet awake until it catches up")
    func sleepyAfterClockSetBack() {
        var resolver = PetMoodResolver()
        _ = resolver.update(with: snapshot(at: 3_600, cpu: 0.02))
        #expect(resolver.update(with: snapshot(at: 0, cpu: 0.02)) == .calm)
        #expect(resolver.update(with: snapshot(at: 180, cpu: 0.02)) == .sleepy)
    }

    @Test("A detail only acts out its own metric")
    func detailMood() {
        let busyAndHot = snapshot(cpu: 0.95, hottest: 95)
        #expect(PetMood.forDetail(.temperature, in: busyAndHot) == .hot)
        #expect(PetMood.forDetail(.cpu, in: busyAndHot) == .busy)
        #expect(PetMood.forDetail(.memory, in: busyAndHot) == .calm)
        #expect(PetMood.forDetail(.network, in: snapshot(network: 0.9)) == .carrying)
    }
}

@Suite("Pet visits")
struct PetDirectorTests {
    private func director(_ rng: inout SeededGenerator) -> PetDirector {
        PetDirector(now: start, random: &rng)
    }

    @Test("The first random visit falls inside the configured gap")
    func firstGap() {
        for seed in 0..<50 as Range<UInt64> {
            var rng = SeededGenerator(state: seed)
            let gap = director(&rng).nextVisit.timeIntervalSince(start)
            #expect((180...480).contains(gap))
        }
    }

    @Test("A random visit crosses, then leaves when the mood is ordinary")
    func randomVisit() {
        var rng = SeededGenerator(state: 1)
        var director = director(&rng)
        let due = director.nextVisit
        #expect(director.step(mood: .calm, at: due.addingTimeInterval(-1), random: &rng) == .none)
        #expect(director.step(mood: .calm, at: due, random: &rng) == .enter(duration: 24))
        #expect(director.step(mood: .calm, at: due.addingTimeInterval(10), random: &rng) == .none)
        #expect(director.step(mood: .calm, at: due.addingTimeInterval(24), random: &rng) == .leave)
        #expect(director.phase == .away)
        let gap = director.nextVisit.timeIntervalSince(due.addingTimeInterval(24))
        #expect((180...480).contains(gap))
    }

    @Test("A spike brings the pet at once, running")
    func spike() {
        var rng = SeededGenerator(state: 2)
        var director = director(&rng)
        #expect(director.step(mood: .calm, at: start.addingTimeInterval(1), random: &rng) == .none)
        #expect(director.step(mood: .busy, at: start.addingTimeInterval(2), random: &rng) == .enter(duration: 14))
    }

    @Test("A spike still going on at the far end keeps the pet there until it passes")
    func lingers() {
        var rng = SeededGenerator(state: 3)
        var director = director(&rng)
        _ = director.step(mood: .hot, at: start, random: &rng)
        #expect(director.step(mood: .hot, at: start.addingTimeInterval(24), random: &rng) == .linger)
        #expect(director.step(mood: .hot, at: start.addingTimeInterval(200), random: &rng) == .linger)
        #expect(director.step(mood: .calm, at: start.addingTimeInterval(201), random: &rng) == .leave)
    }

    @Test("A busy machine brings the pet once per spike, and no sooner than the cooldown")
    func cooldown() {
        var rng = SeededGenerator(state: 4)
        // Random visits pushed out of the way, so only spikes are in play.
        var director = PetDirector(now: start, configuration: .init(visitGap: 3600...3600), random: &rng)
        #expect(director.step(mood: .busy, at: start, random: &rng) == .enter(duration: 14))
        #expect(director.step(mood: .calm, at: start.addingTimeInterval(14), random: &rng) == .leave)
        // A new spike two minutes later is inside the cooldown.
        #expect(director.step(mood: .busy, at: start.addingTimeInterval(120), random: &rng) == .none)
        // Staying busy is not a new spike, even after the cooldown.
        #expect(director.step(mood: .busy, at: start.addingTimeInterval(400), random: &rng) == .none)
        _ = director.step(mood: .calm, at: start.addingTimeInterval(401), random: &rng)
        #expect(director.step(mood: .busy, at: start.addingTimeInterval(402), random: &rng) == .enter(duration: 14))
    }

    @Test("An interrupted visit is over, and the next is a full gap away")
    func interrupt() {
        var rng = SeededGenerator(state: 5)
        var director = director(&rng)
        _ = director.step(mood: .busy, at: start, random: &rng)
        director.interrupt(at: start.addingTimeInterval(5), random: &rng)
        #expect(director.phase == .away)
        #expect(director.nextVisit.timeIntervalSince(start.addingTimeInterval(5)) >= 180)
    }

    @Test("A clock set back mid-crossing moves the visit's deadlines back with it")
    func clockSetBack() {
        var rng = SeededGenerator(state: 7)
        var director = PetDirector(now: start, configuration: .init(visitGap: 3600...3600), random: &rng)
        let crossingStart = start.addingTimeInterval(7_200)
        #expect(director.step(mood: .calm, at: crossingStart, random: &rng) == .enter(duration: 24))

        // Ten seconds in, the clock goes back an hour: the crossing still ends
        // fourteen seconds later, not an hour and fourteen.
        #expect(director.step(mood: .calm, at: crossingStart.addingTimeInterval(10), random: &rng) == .none)
        let setBack = crossingStart.addingTimeInterval(10 - 3_600)
        #expect(director.step(mood: .calm, at: setBack, random: &rng) == .none)
        #expect(director.step(mood: .calm, at: setBack.addingTimeInterval(14), random: &rng) == .leave)
        #expect(director.nextVisit.timeIntervalSince(setBack.addingTimeInterval(14)) == 3_600)
    }

    @Test("Summoning brings the pet on the next sample")
    func summon() {
        var rng = SeededGenerator(state: 6)
        var director = director(&rng)
        director.summon(at: start)
        #expect(director.step(mood: .calm, at: start.addingTimeInterval(1), random: &rng) == .enter(duration: 24))
    }

    @Test("About one detail opening in four finds the pet")
    func detailChance() {
        var rng = SeededGenerator(state: 7)
        let director = director(&rng)
        let hits = (0..<4000).count { _ in director.showsInDetail(random: &rng) }
        #expect((850...1150).contains(hits))
    }
}

@Suite("Pet art")
struct PetArtTests {
    @Test("Every pose is drawn on its 16 × 14 grid with defined colours")
    func sheetsAreWellFormed() {
        for pet in TouchBarPet.allCases {
            guard let sheet = PetArt.sheet(for: pet) else { continue }
            for grid in sheet.grids {
                #expect(grid.count == PetArt.bodyHeight, "\(pet)")
                for row in grid {
                    #expect(row.count == PetArt.bodyWidth, "\(pet): \(row)")
                    for cell in row where cell != "." {
                        #expect(sheet.palette[cell] != nil, "\(pet): \(cell)")
                    }
                }
            }
        }
    }

    @Test("Every pet has a frame for every mood and pose, and none for off")
    func everyMood() {
        for pet in TouchBarPet.allCases where pet != .off {
            for mood in PetMood.allCases {
                for pose in PetArt.Pose.allCases {
                    let frame = PetArt.frame(for: pet, mood: mood, pose: pose)
                    #expect(frame?.width == PetArt.canvasSize && frame?.height == PetArt.canvasSize)
                    #expect(frame?.rgba.count == PetArt.canvasSize * PetArt.canvasSize * 4)
                    #expect((frame?.opaquePixelCount ?? 0) > 60, "\(pet) \(mood) \(pose)")
                }
            }
        }
        #expect(PetArt.frame(for: .off, mood: .calm, pose: .stand) == nil)
    }

    @Test("The poses differ from one another, so every change shows")
    func posesDiffer() {
        for pet in TouchBarPet.allCases where pet != .off {
            let poses: [PetArt.Pose] = [.stand, .step, .blink, .jump, .asleep]
            let frames = poses.compactMap { PetArt.frame(for: pet, mood: .calm, pose: $0) }
            #expect(Set(frames.map(\.rgba)).count == poses.count, "\(pet)")
            // The z breathes between the two sleeping frames.
            #expect(PetArt.frame(for: pet, mood: .calm, pose: .asleep) != PetArt.frame(for: pet, mood: .calm, pose: .asleepBreath))
        }
    }

    @Test("A mood shows: heat recolours, a surprise adds a mark")
    func moodsShow() throws {
        let calm = try #require(PetArt.frame(for: .coco, mood: .calm, pose: .stand))
        let hot = try #require(PetArt.frame(for: .coco, mood: .hot, pose: .stand))
        #expect(calm != hot)
        let surprised = try #require(PetArt.frame(for: .coco, mood: .calm, pose: .stand, surprised: true))
        #expect(surprised.opaquePixelCount > calm.opaquePixelCount)
        // Props sit above the body, so the canvas's top rows are free otherwise.
        #expect((0..<PetArt.canvasSize).allSatisfy { calm.alpha(x: $0, y: 0) == 0 })
    }

    @Test("Pixels are either opaque or fully clear")
    func binaryAlpha() throws {
        let frame = try #require(PetArt.frame(for: .frog, mood: .drained, pose: .step))
        for index in stride(from: 3, to: frame.rgba.count, by: 4) {
            #expect(frame.rgba[index] == 0 || frame.rgba[index] == 0xFF)
        }
    }
}

@Suite("Pet routes")
struct PetRouteTests {
    @Test("A crossing starts and ends where asked, on time, without gaps")
    func wellFormed() {
        for seed in 0..<40 as Range<UInt64> {
            for mood in PetMood.allCases {
                var rng = SeededGenerator(state: seed)
                let route = PetRoute.crossing(from: -10, to: 300, duration: 24, mood: mood, random: &rng)
                #expect(route.segments.first?.start == 0)
                #expect(abs(route.duration - 24) < 1e-9)
                #expect(route.segments.first?.fromX == -10)
                #expect(route.segments.last?.toX == 300)
                for (a, b) in zip(route.segments, route.segments.dropFirst()) {
                    #expect(abs(a.end - b.start) < 1e-9)
                    #expect(a.toX == b.fromX)
                }
                // Never backwards: the pet only ever heads for the far end.
                #expect(route.segments.allSatisfy { $0.toX >= $0.fromX })
            }
        }
    }

    @Test("A busy pet hops but never stops; a sleepy one stops twice")
    func stopsFollowTheMood() {
        var rng = SeededGenerator(state: 9)
        let busy = PetRoute.crossing(from: 0, to: 300, duration: 14, mood: .busy, random: &rng)
        #expect(busy.segments.filter { $0.move == .hop }.count == 2)
        #expect(!busy.segments.contains { $0.move == .pause })
        let sleepy = PetRoute.crossing(from: 0, to: 300, duration: 30, mood: .sleepy, random: &rng)
        #expect(sleepy.segments.filter { $0.move == .pause }.count == 2)
    }

    @Test("Stops shrink rather than eat a short crossing")
    func shortCrossing() {
        var rng = SeededGenerator(state: 10)
        let route = PetRoute.crossing(from: 0, to: 100, duration: 3, mood: .sleepy, random: &rng)
        let walking = route.segments.filter { $0.move == .walk }.reduce(0) { $0 + $1.end - $1.start }
        #expect(walking >= 1.5 - 1e-9)
    }

    @Test("The pose walks, blinks in a pause and jumps in a hop")
    func poses() {
        let route = PetRoute(segments: [
            .init(move: .walk, start: 0, end: 1, fromX: 0, toX: 10),
            .init(move: .pause, start: 1, end: 3, fromX: 10, toX: 10),
            .init(move: .hop, start: 3, end: 3.45, fromX: 10, toX: 10),
        ])
        #expect(route.pose(at: 0.1, stepInterval: 0.3) == .stand)
        #expect(route.pose(at: 0.4, stepInterval: 0.3) == .step)
        #expect(route.pose(at: 1.5, stepInterval: 0.3) == .stand)
        #expect(route.pose(at: 2.05, stepInterval: 0.3) == .blink)
        #expect(route.pose(at: 3.2, stepInterval: 0.3) == .jump)
    }

    @Test("Keyframes run through every segment's end, and every hop goes up and back")
    func keyframes() throws {
        let route = PetRoute(segments: [
            .init(move: .walk, start: 0, end: 2, fromX: 0, toX: 10),
            .init(move: .hop, start: 2, end: 3, fromX: 10, toX: 10),
            .init(move: .walk, start: 3, end: 4, fromX: 10, toX: 20),
        ])
        let path = route.positionKeyframes
        #expect(path.values == [0, 10, 10, 20])
        #expect(path.keyTimes == [0, 0.5, 0.75, 1])
        let hops = try #require(route.hopKeyframes)
        #expect(hops.values == [0, 0, PetRoute.hopHeight, 0, 0])
        #expect(hops.keyTimes.first == 0 && hops.keyTimes.last == 1)
        #expect(zip(hops.keyTimes, hops.keyTimes.dropFirst()).allSatisfy { $0 <= $1 })
        // A route without hops needs no height animation at all.
        #expect(PetRoute(segments: [route.segments[0]]).hopKeyframes == nil)
    }

    @Test("Pose changes start at the asked time and never repeat a pose")
    func poseChanges() {
        var rng = SeededGenerator(state: 11)
        let route = PetRoute.crossing(from: 0, to: 300, duration: 24, mood: .calm, random: &rng)
        let changes = route.poseChanges(from: 5, stepInterval: 0.3)
        #expect(changes.first?.time == 0)
        for (a, b) in zip(changes, changes.dropFirst()) {
            #expect(a.time < b.time)
            #expect(a.pose != b.pose)
        }
        #expect(changes.contains { $0.pose == .blink } || changes.contains { $0.pose == .jump })
    }
}

@Suite("Pet behaviour")
struct PetBehaviourTests {
    @Test("A wandering pet never leaves its range")
    func staysInRange() {
        var rng = SeededGenerator(state: 12)
        var behaviour = PetBehaviour(range: -40...10)
        for _ in 0..<2000 {
            _ = behaviour.next(mood: .busy, random: &rng)
            #expect((-40...10).contains(behaviour.offset))
        }
    }

    @Test("Walking faces the way it goes")
    func facesItsWay() {
        var rng = SeededGenerator(state: 13)
        var behaviour = PetBehaviour(range: -40...40)
        for _ in 0..<500 {
            if case let .walk(distance) = behaviour.next(mood: .calm, random: &rng) {
                #expect(behaviour.facesLeading == (distance < 0))
            }
        }
    }

    @Test("A busy pet never falls asleep; a calm one does, but not straight away")
    func sleepDependsOnMood() {
        var rng = SeededGenerator(state: 14)
        var busy = PetBehaviour(range: -40...10)
        for _ in 0..<1000 { #expect(busy.next(mood: .busy, random: &rng) != .sleep) }

        var calm = PetBehaviour(range: -40...10)
        var activities: [PetBehaviour.Activity] = []
        for _ in 0..<400 { activities.append(calm.next(mood: .calm, random: &rng)) }
        #expect(!activities.prefix(PetBehaviour.wakefulness - 1).contains(.sleep))
        #expect(activities.contains(.sleep))
        #expect(activities.contains(.hop))
        #expect(activities.contains { if case .walk = $0 { true } else { false } })
    }

    @Test("A nap ends on its own, and at once when the machine gets busy")
    func waking() {
        var rng = SeededGenerator(state: 15)
        var behaviour = PetBehaviour(range: -40...10)
        while !behaviour.isAsleep { _ = behaviour.next(mood: .calm, random: &rng) }
        #expect(behaviour.next(mood: .busy, random: &rng) == .hop)
        #expect(!behaviour.isAsleep)

        while !behaviour.isAsleep { _ = behaviour.next(mood: .calm, random: &rng) }
        var naps = 0
        while behaviour.isAsleep, naps < 20 {
            _ = behaviour.next(mood: .calm, random: &rng)
            naps += 1
        }
        #expect((6...14).contains(naps))
    }

    @Test("A sleepy machine has a sleeping pet")
    func sleepyMachine() {
        var rng = SeededGenerator(state: 16)
        var behaviour = PetBehaviour(range: -40...10)
        for _ in 0..<20 { #expect(behaviour.next(mood: .sleepy, random: &rng) == .sleep) }
    }
}
