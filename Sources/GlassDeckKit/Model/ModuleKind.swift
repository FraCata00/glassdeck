import Foundation

/// Anything a surface paints with an accent colour, an icon and a name: the
/// scalar metrics and the non-scalar modules alike.
///
/// It exists so `Theme` does not need one overload per enum, and so a card
/// header can be written once for both.
public protocol Accented: Identifiable, Sendable {
    var title: String { get }
    var symbolName: String { get }
    /// Hue anchor (0...1) for the accent colour.
    var hue: Double { get }
}

extension MetricKind: Accented {}

/// The panel sections that are not a single number.
///
/// Deliberately not part of `MetricKind`. Everything in that enum is one
/// fraction of a whole, and the whole pipeline is built on that: `fraction(for:)`,
/// the rolling history behind every sparkline, the ring gauges, the bars in the
/// status item, the Touch Bar strip, the temperature alert. A list of paired
/// devices — each with its own charge, and sometimes three of them — has no such
/// number. Inventing one would put a meaningless ring in the panel and a
/// meaningless bar in the menu bar, so these render as cards of their own
/// instead, and the two enums stay honest about what they are.
public enum ModuleKind: String, Sendable, CaseIterable, Codable, Identifiable, Accented {
    case bluetooth

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bluetooth: "Bluetooth"
        }
    }

    public var symbolName: String {
        switch self {
        // There is no Bluetooth glyph in SF Symbols, and the radio waves are
        // what the system itself uses for a wireless link.
        case .bluetooth: "antenna.radiowaves.left.and.right"
        }
    }

    public var hue: Double {
        switch self {
        case .bluetooth: 0.66 // blue, as the system paints Bluetooth itself
        }
    }

    /// Modules enabled the first time the app runs.
    ///
    /// All of them, because a module hides itself when it has nothing to say —
    /// the Bluetooth card until a device with a battery is paired.
    public static let defaultSelection: [ModuleKind] = allCases
}
