import Foundation

/// A time zone the user has put on the clock card.
///
/// Stored by identifier rather than by offset, so a zone follows its own summer
/// time instead of drifting an hour twice a year.
public struct ClockZone: Sendable, Equatable, Codable, Identifiable, Hashable {
    public var identifier: String
    /// What the row is called. Defaults to the city in the identifier, and the
    /// user can rename it — "Home", "the office", a colleague's name.
    public var label: String

    public init(identifier: String, label: String? = nil) {
        self.identifier = identifier
        self.label = label ?? Self.cityName(for: identifier)
    }

    public var id: String { identifier }

    public var timeZone: TimeZone? { TimeZone(identifier: identifier) }

    /// What the row is actually called on screen.
    ///
    /// The stored label is allowed to be empty so that clearing the field to
    /// retype it does not refill itself with the city name after every
    /// keystroke; the fallback happens here instead.
    public var displayLabel: String {
        label.isEmpty ? Self.cityName(for: identifier) : label
    }

    /// `Europe/Rome` → `Rome`, `America/Argentina/Buenos_Aires` → `Buenos Aires`.
    ///
    /// Derived from the identifier rather than asked of the system, because what
    /// the system offers is the name of the *zone* — "Central European Standard
    /// Time" — and nobody labels a clock with that.
    public static func cityName(for identifier: String) -> String {
        (identifier.split(separator: "/").last.map(String.init) ?? identifier)
            .replacingOccurrences(of: "_", with: " ")
    }

    /// The region an identifier belongs to, used to group the picker.
    public static func region(for identifier: String) -> String {
        guard let first = identifier.split(separator: "/").first, identifier.contains("/") else {
            return L.t("clock.otherRegion", "Other")
        }
        return String(first).replacingOccurrences(of: "_", with: " ")
    }
}

/// Which day it is somewhere else, relative to here.
public enum DayShift: Int, Sendable, Equatable {
    // Two days either way is not a curiosity: Kiritimati (+14) is 25 hours
    // ahead of Niue (-11), so for an hour each day it is two dates ahead.
    case twoDaysBefore = -2
    case yesterday = -1
    case today = 0
    case tomorrow = 1
    case twoDaysAfter = 2

    public var caption: String? {
        switch self {
        case .twoDaysBefore: L.t("clock.twoDaysBefore", "2 days ago")
        case .yesterday: L.t("clock.yesterday", "yesterday")
        case .today: nil
        case .tomorrow: L.t("clock.tomorrow", "tomorrow")
        case .twoDaysAfter: L.t("clock.twoDaysAfter", "in 2 days")
        }
    }
}

/// One row of the clock card: what time it is there, and how far that is from here.
public struct ClockReading: Sendable, Equatable, Identifiable {
    public var zone: ClockZone
    public var time: String
    public var dayShift: DayShift
    /// `+9h`, `-4h30`, or the words for no difference at all.
    public var offset: String

    public init(zone: ClockZone, time: String, dayShift: DayShift, offset: String) {
        self.zone = zone
        self.time = time
        self.dayShift = dayShift
        self.offset = offset
    }

    public var id: String { zone.id }

    /// The line under the time: the offset, and the day when it is not this one.
    public var caption: String {
        guard let day = dayShift.caption else { return offset }
        return "\(offset) · \(day)"
    }
}

/// Turns a time zone and an instant into the three strings the card draws.
///
/// Pure, and every input is a parameter — including the reference zone and the
/// locale — so the awkward cases (half-hour offsets, a date line crossing, a
/// zone on summer time when here is not) can be tested without touching the
/// clock of the machine running the tests.
public enum WorldClock {
    public static func reading(
        for zone: ClockZone,
        at date: Date,
        reference: TimeZone = .current,
        locale: Locale = .current
    ) -> ClockReading {
        guard let timeZone = zone.timeZone else {
            // A zone identifier that macOS no longer knows: the row stays, so
            // the user can see which one to remove.
            return ClockReading(zone: zone, time: L.t("value.na", "n/a"), dayShift: .today, offset: "")
        }
        return ClockReading(
            zone: zone,
            time: time(in: timeZone, at: date, locale: locale),
            dayShift: dayShift(of: timeZone, from: reference, at: date),
            offset: offsetLabel(of: timeZone, from: reference, at: date)
        )
    }

    /// The wall clock in a zone, in the format that locale writes times in.
    public static func time(in timeZone: TimeZone, at date: Date, locale: Locale = .current) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone)
        )
    }

    /// How far ahead or behind a zone runs, at this instant.
    ///
    /// Measured at the given date rather than from the zone's standard offset,
    /// which is the only way to be right in the weeks when one side has changed
    /// to summer time and the other has not.
    public static func offsetLabel(of timeZone: TimeZone, from reference: TimeZone, at date: Date) -> String {
        let difference = timeZone.secondsFromGMT(for: date) - reference.secondsFromGMT(for: date)
        guard difference != 0 else { return L.t("clock.same", "same time") }

        let sign = difference > 0 ? "+" : "-"
        let magnitude = abs(difference)
        let hours = magnitude / 3_600
        let minutes = (magnitude % 3_600) / 60
        return minutes == 0
            ? "\(sign)\(hours)h"
            : String(format: "%@%ldh%02ld", sign, hours, minutes)
    }

    /// Whether it is already tomorrow there, or still yesterday.
    ///
    /// Compared as calendar dates in the two zones: no zone is a full day away
    /// from another, so the answer can only be one of three.
    public static func dayShift(of timeZone: TimeZone, from reference: TimeZone, at date: Date) -> DayShift {
        let days = day(of: date, in: timeZone) - day(of: date, in: reference)
        // No two zones are more than two dates apart; clamped all the same, so
        // a zone database that one day disagrees cannot leave the row blank.
        return DayShift(rawValue: min(2, max(-2, days))) ?? .today
    }

    /// The calendar date in a zone, as a count of days, so two of them can be
    /// subtracted across a month or a year end.
    private static func day(of date: Date, in timeZone: TimeZone) -> Int {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let parts = local.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let midnight = utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)) ?? date
        return Int((midnight.timeIntervalSinceReferenceDate / 86_400).rounded(.down))
    }
}
