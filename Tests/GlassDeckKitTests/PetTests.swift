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

    @Test("Busy enters at 85 % and leaves only below 70 %")
    func busyHysteresis() {
        var resolver = PetMoodResolver()
        #expect(resolver.update(with: snapshot(cpu: 0.84)) == .calm)
        #expect(resolver.update(with: snapshot(cpu: 0.86)) == .busy)
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
            #expect((480...1500).contains(gap))
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
        #expect((480...1500).contains(gap))
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
        #expect(director.step(mood: .hot, at: start.addingTimeInterval(200), random: &rng) == .none)
        #expect(director.step(mood: .calm, at: start.addingTimeInterval(201), random: &rng) == .leave)
    }

    @Test("A busy machine brings the pet once per spike, and no sooner than the cooldown")
    func cooldown() {
        var rng = SeededGenerator(state: 4)
        var director = director(&rng)
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
        #expect(director.nextVisit.timeIntervalSince(start.addingTimeInterval(5)) >= 480)
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
            for grid in [sheet.walkA, sheet.walkB, sheet.asleep] {
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

    @Test("Every pet has two frames for every mood and pose, and none for off")
    func everyMood() {
        for pet in TouchBarPet.allCases where pet != .off {
            for mood in PetMood.allCases {
                for pose in [PetArt.Pose.moving, .resting] {
                    let frames = PetArt.frames(for: pet, mood: mood, pose: pose)
                    #expect(frames.count == 2)
                    for frame in frames {
                        #expect(frame.width == PetArt.canvasSize && frame.height == PetArt.canvasSize)
                        #expect(frame.rgba.count == PetArt.canvasSize * PetArt.canvasSize * 4)
                        #expect(frame.opaquePixelCount > 60)
                    }
                }
            }
        }
        #expect(PetArt.frames(for: .off, mood: .calm, pose: .moving).isEmpty)
    }

    @Test("The walk frames differ, so the pet visibly walks")
    func walkAnimates() {
        for pet in TouchBarPet.allCases where pet != .off {
            let frames = PetArt.frames(for: pet, mood: .calm, pose: .moving)
            #expect(frames[0] != frames[1], "\(pet)")
        }
    }

    @Test("A mood shows: heat recolours, a surprise adds a mark")
    func moodsShow() {
        let calm = PetArt.frames(for: .coco, mood: .calm, pose: .moving)[0]
        let hot = PetArt.frames(for: .coco, mood: .hot, pose: .moving)[0]
        #expect(calm != hot)
        let surprised = PetArt.frames(for: .coco, mood: .calm, pose: .moving, surprised: true)[0]
        #expect(surprised.opaquePixelCount > calm.opaquePixelCount)
        // Props sit above the body, so the canvas's top rows are free otherwise.
        #expect((0..<PetArt.canvasSize).allSatisfy { calm.alpha(x: $0, y: 0) == 0 })
    }

    @Test("Pixels are either opaque or fully clear")
    func binaryAlpha() {
        let frame = PetArt.frames(for: .frog, mood: .drained, pose: .moving)[1]
        for index in stride(from: 3, to: frame.rgba.count, by: 4) {
            #expect(frame.rgba[index] == 0 || frame.rgba[index] == 0xFF)
        }
    }
}
