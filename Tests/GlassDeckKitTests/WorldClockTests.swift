import Foundation
import Testing
@testable import GlassDeckKit

@Suite("World clock")
struct WorldClockTests {
    private let rome = TimeZone(identifier: "Europe/Rome")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let kolkata = TimeZone(identifier: "Asia/Kolkata")!
    private let london = TimeZone(identifier: "Europe/London")!

    /// 2026-02-25 14:13:20 in Rome, which is winter in both hemispheres of
    /// interest here — no summer time anywhere in these zones.
    private let winter = Date(timeIntervalSince1970: 1_772_025_200)
    /// Half past midnight in Rome, which is still the day before in California.
    private let pastMidnightInRome = Date(timeIntervalSince1970: 1_772_062_200)
    /// Inside the three weeks when the United States has changed to summer time
    /// and Europe has not.
    private let mismatchedDST = Date(timeIntervalSince1970: 1_774_008_000)

    private let english = Locale(identifier: "en_GB")

    @Test("A zone reads the wall clock of that zone")
    func timeInZone() {
        #expect(WorldClock.time(in: rome, at: winter, locale: english) == "14:13")
        #expect(WorldClock.time(in: tokyo, at: winter, locale: english) == "22:13")
        #expect(WorldClock.time(in: losAngeles, at: winter, locale: english) == "5:13")
    }

    @Test("The offset is whole hours where it is whole hours, and minutes where it is not")
    func offsets() {
        #expect(WorldClock.offsetLabel(of: rome, from: rome, at: winter) == "same time")
        #expect(WorldClock.offsetLabel(of: tokyo, from: rome, at: winter) == "+8h")
        #expect(WorldClock.offsetLabel(of: losAngeles, from: rome, at: winter) == "-9h")
        #expect(WorldClock.offsetLabel(of: kolkata, from: london, at: winter) == "+5h30")
        #expect(WorldClock.offsetLabel(of: london, from: kolkata, at: winter) == "-5h30")
    }

    @Test("Offsets are measured at the instant, so a summer time mismatch is not an hour out")
    func summerTimeMismatch() {
        // Rome and New York are six hours apart for most of the year. Between
        // the American change and the European one they are five, and taking the
        // zones' standard offsets instead of asking them about this date is
        // exactly how that hour gets lost.
        #expect(WorldClock.offsetLabel(of: rome, from: newYork, at: winter) == "+6h")
        #expect(WorldClock.offsetLabel(of: rome, from: newYork, at: mismatchedDST) == "+5h")
    }

    @Test("A zone on the other side of midnight is marked as another day")
    func dayShifts() {
        #expect(WorldClock.dayShift(of: tokyo, from: rome, at: winter) == .today)
        #expect(WorldClock.dayShift(of: losAngeles, from: rome, at: pastMidnightInRome) == .yesterday)
        #expect(WorldClock.dayShift(of: tokyo, from: losAngeles, at: pastMidnightInRome) == .tomorrow)
    }

    @Test("A reading pairs the time with how far away it is")
    func readings() {
        let zone = ClockZone(identifier: "Asia/Tokyo")
        let reading = WorldClock.reading(for: zone, at: winter, reference: rome, locale: english)

        #expect(reading.time == "22:13")
        #expect(reading.caption == "+8h")

        let california = WorldClock.reading(
            for: ClockZone(identifier: "America/Los_Angeles"),
            at: pastMidnightInRome,
            reference: rome,
            locale: english
        )
        #expect(california.caption == "-9h · yesterday")
    }

    @Test("A zone this macOS no longer knows keeps its row instead of vanishing")
    func unknownZone() {
        let reading = WorldClock.reading(for: ClockZone(identifier: "Mars/Olympus"), at: winter)
        #expect(reading.time == "n/a")
        #expect(reading.zone.displayLabel == "Olympus")
    }

    @Test("Labels come from the identifier, and can be overridden")
    func labels() {
        #expect(ClockZone.cityName(for: "Europe/Rome") == "Rome")
        #expect(ClockZone.cityName(for: "America/Argentina/Buenos_Aires") == "Buenos Aires")
        #expect(ClockZone.cityName(for: "UTC") == "UTC")

        #expect(ClockZone(identifier: "Europe/Rome").displayLabel == "Rome")
        #expect(ClockZone(identifier: "Europe/Rome", label: "Home").displayLabel == "Home")
        // Cleared to be retyped: the city stands in until it is.
        #expect(ClockZone(identifier: "Europe/Rome", label: "").displayLabel == "Rome")
    }

    @Test("Regions group the picker, and a zone without one lands in Other")
    func regions() {
        #expect(ClockZone.region(for: "Europe/Rome") == "Europe")
        #expect(ClockZone.region(for: "America/Argentina/Buenos_Aires") == "America")
        #expect(ClockZone.region(for: "UTC") == "Other")
    }

    @Test("Zones survive a round trip through the settings store")
    func codable() throws {
        let zones = [ClockZone(identifier: "Europe/Rome", label: "Home"), ClockZone(identifier: "Asia/Tokyo")]
        let data = try JSONEncoder().encode(zones)
        #expect(try JSONDecoder().decode([ClockZone].self, from: data) == zones)
    }
}
