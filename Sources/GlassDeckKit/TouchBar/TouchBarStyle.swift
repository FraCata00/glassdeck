import Foundation

/// How the metric panels on the full and compact bar are drawn.
///
/// Only the painting changes: every style reads the same snapshot at the same
/// cadence, so choosing one costs nothing in sampling. The expanded detail of
/// a metric follows the style too; only the Control Strip meter keeps its own
/// look, since a 42 pt chip has no room for one.
public enum TouchBarStyle: String, Sendable, CaseIterable, Identifiable {
    /// Translucent chips with a sparkline: the look GlassDeck shipped with.
    case glass
    /// No chips, hairline rules, large monospaced figures and a segmented meter.
    case instrument
    /// The chip is the gauge: a capsule that fills up to the reading.
    case capsule
    /// The history fills the whole cell and the figure sits on top of it.
    case ambient
    /// A small ring gauge per metric, as in the panel.
    case rings
    /// One line of monospaced text in a single colour, with a character sparkline.
    case terminal
    /// The history as discrete columns, the latest one at full strength.
    case histogram
    /// Grey until a metric needs attention; the colour says the state, not the metric.
    case signal
    /// Each chip takes its metric's colour, with the level as a rule along the bottom.
    case tinted

    /// What sits behind an item on the bar, beyond what the style paints itself.
    public enum Chrome: Sendable {
        /// A translucent rounded chip.
        case chip
        /// A hairline rule on the leading edge, dividing the bar into cells.
        case hairline
        /// Nothing: the style's own paint is the whole of it.
        case none
    }

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .glass: L.t("touchbar.style.glass", "Glass")
        case .instrument: L.t("touchbar.style.instrument", "Instrument")
        case .capsule: L.t("touchbar.style.capsule", "Capsule")
        case .ambient: L.t("touchbar.style.ambient", "Ambient")
        case .rings: L.t("touchbar.style.rings", "Rings")
        case .terminal: L.t("touchbar.style.terminal", "Terminal")
        case .histogram: L.t("touchbar.style.histogram", "Histogram")
        case .signal: L.t("touchbar.style.signal", "Signal")
        case .tinted: L.t("touchbar.style.tinted", "Tinted glass")
        }
    }

    /// One line under the title in the style picker.
    public var summary: String {
        switch self {
        case .glass: L.t("touchbar.style.glass.summary", "Translucent chips with a sparkline.")
        case .instrument: L.t("touchbar.style.instrument.summary", "Hairlines, monospaced figures and a segmented meter.")
        case .capsule: L.t("touchbar.style.capsule.summary", "Each chip fills up to its reading.")
        case .ambient: L.t("touchbar.style.ambient.summary", "The history fills the cell, the figure sits on top.")
        case .rings: L.t("touchbar.style.rings.summary", "A small ring gauge per metric, as in the panel.")
        case .terminal: L.t("touchbar.style.terminal.summary", "One line of monospaced text in a single colour.")
        case .histogram: L.t("touchbar.style.histogram.summary", "The last samples as columns.")
        case .signal: L.t("touchbar.style.signal.summary", "Grey until a metric needs attention.")
        case .tinted: L.t("touchbar.style.tinted.summary", "Each chip in its metric's colour.")
        }
    }

    /// Whether the panel draws the history at all. The controller skips
    /// copying the ring buffer into panels whose style would not look at it.
    public var drawsHistory: Bool {
        switch self {
        case .glass, .ambient, .terminal, .histogram: true
        case .instrument, .capsule, .rings, .signal, .tinted: false
        }
    }

    /// The plain background of an item in this style, shared by the panels and
    /// the battery chip so the chip never stands out as the only boxed item on
    /// an open bar. The styles that paint a shape of their own — capsule,
    /// ambient, signal, tinted — draw that shape instead on the panels, and the
    /// battery chip, which has no such shape, falls back to the plain chip.
    public var chrome: Chrome {
        switch self {
        case .glass, .capsule, .ambient, .histogram, .signal, .tinted: .chip
        case .instrument: .hairline
        case .rings, .terminal: .none
        }
    }

    /// Whether memory's pressure light is drawn on top. The signal style says
    /// the same thing with the whole cell, so a dot would only repeat it.
    public var marksMemoryPressure: Bool { self != .signal }
}

/// The arithmetic behind the styles, kept out of the views so it can be tested
/// without a Touch Bar.
public enum TouchBarHistory {
    /// The characters the terminal style draws its sparkline with, lowest first.
    public static let blocks: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    /// Vertical range a curve is drawn in.
    ///
    /// Metrics such as memory and disk barely move, and drawing them against the
    /// full 0–100 % scale turns the curve into a flat slab. When the observed
    /// spread is small the window zooms in around it, which is what makes the
    /// Touch Bar graph worth glancing at.
    public static func window(for values: [Double]) -> ClosedRange<Double> {
        let minimum = values.min().map(\.clamped01) ?? 0
        let maximum = values.max().map(\.clamped01) ?? 1
        let spread = maximum - minimum
        guard spread < 0.08 else { return minimum...maximum }
        let centre = (minimum + maximum) / 2
        let lower = max(0, centre - 0.04)
        return lower...(lower + 0.08)
    }

    /// Where `value` falls inside `window`, as a fraction in `0...1`.
    public static func normalised(_ value: Double, in window: ClosedRange<Double>) -> Double {
        let span = window.upperBound - window.lowerBound
        guard span > 0 else { return 0 }
        return ((value.clamped01 - window.lowerBound) / span).clamped01
    }

    /// How many columns of at least 3 pt fit across `width`, at most 16.
    public static func columnCount(width: Double) -> Int {
        min(16, max(1, Int(width / 3)))
    }

    /// The latest `count` samples as column heights in `0...1`, oldest first.
    ///
    /// Scaled against the whole history rather than only the columns shown, so
    /// a quiet minute after a busy one still looks quiet. Never quite zero: an
    /// empty column reads as a missing sample rather than an idle one.
    public static func columns(_ history: [Double], count: Int) -> [Double] {
        guard count > 0, !history.isEmpty else { return [] }
        let window = window(for: history)
        return history.suffix(count).map { max(0.08, normalised($0, in: window)) }
    }

    /// The latest `count` samples as block characters, for the terminal style.
    public static func sparkline(_ history: [Double], count: Int) -> String {
        guard count > 0, !history.isEmpty else { return "" }
        let window = window(for: history)
        let top = blocks.count - 1
        return String(history.suffix(count).map { value in
            blocks[min(top, Int(normalised(value, in: window) * Double(blocks.count)))]
        })
    }

    /// Segments in the instrument meter: ten where they stay legible, six on a
    /// narrow panel.
    public static func meterSegmentCount(width: Double) -> Int {
        width >= 40 ? 10 : 6
    }

    /// How many of `count` meter segments a reading lights.
    ///
    /// Any reading above zero lights at least one, so a metric that is merely
    /// low is not mistaken for one that is off.
    public static func litSegments(_ fraction: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let value = fraction.clamped01
        guard value > 0 else { return 0 }
        return min(count, max(1, Int((value * Double(count)).rounded())))
    }

    /// What the terminal style prints in a panel `characters` wide.
    public struct TerminalLine: Equatable, Sendable {
        /// `nil` when even the shortest reading leaves no room for the name.
        public let title: String?
        public let headline: String
        /// Up to eight block characters, or empty when there is no room.
        public let sparkline: String
    }

    /// Lays out "TITLE headline ▁▃▅" in a fixed number of monospaced characters.
    ///
    /// The headline is the first candidate that fits beside the title; the
    /// title goes when nothing does; the sparkline takes what is left, and is
    /// dropped below three characters, where it would say nothing.
    public static func terminalLine(title: String, candidates: [String], history: [Double], characters: Int) -> TerminalLine {
        let fallback = candidates.last ?? ""
        let fitting = candidates.first { title.count + 1 + $0.count <= characters }
        guard let headline = fitting else {
            return TerminalLine(title: nil, headline: fallback, sparkline: "")
        }
        let room = characters - title.count - 1 - headline.count - 1
        let sparkline = room >= 3 ? sparkline(history, count: min(8, room)) : ""
        return TerminalLine(title: title, headline: headline, sparkline: sparkline)
    }
}
