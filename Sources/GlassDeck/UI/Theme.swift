import AppKit
import GlassDeckKit
import SwiftUI

/// Colour and layout constants shared by every surface, so the window, the menu
/// bar glyph and the Touch Bar all speak the same visual language.
enum Theme {
    static let cornerRadius: CGFloat = 20
    static let tileCornerRadius: CGFloat = 16
    static let panelWidth: CGFloat = 396

    /// Saturation and brightness of every accent, on every surface.
    ///
    /// Kept well below full: system surfaces on macOS use colour to identify a
    /// thing, not to shout, and neon accents fight the glass material. The
    /// panel, the menu bar glyph and the Touch Bar each used to pick their own
    /// pair, so the same metric came out as three slightly different colours.
    static let accentSaturation = 0.64
    static let accentBrightness = 0.94

    /// Accent colour of a metric or a module.
    static func accent(_ kind: some Accented) -> Color {
        Color(hue: kind.hue, saturation: accentSaturation, brightness: accentBrightness)
    }

    /// The same accent for the surfaces drawn in AppKit.
    static func nsAccent(_ kind: some Accented) -> NSColor {
        NSColor(hue: kind.hue, saturation: accentSaturation, brightness: accentBrightness, alpha: 1)
    }

    /// Deeper end of the gauge gradient.
    static func accentShade(_ kind: some Accented) -> Color {
        Color(hue: (kind.hue + 0.04).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.66)
    }

    /// Sweep used by ring gauges and sparkline strokes.
    static func gradient(_ kind: some Accented) -> LinearGradient {
        LinearGradient(
            colors: [accentShade(kind), accent(kind)],
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        )
    }

    /// Background of the small rounded icon chip that heads every card, the same
    /// device System Settings uses to identify a row at a glance.
    static func iconChip(_ kind: some Accented) -> Color {
        accent(kind).opacity(0.22)
    }

    /// The glass tint that marks the selected gauge or the focused card.
    ///
    /// A tint rather than a hairline border: Liquid Glass reads selection as
    /// the material taking on colour, the way a prominent glass button does,
    /// and a 1 pt ring around a glass circle mostly read as an edge.
    static func selectionTint(_ kind: some Accented) -> Color {
        accent(kind).opacity(0.28)
    }

    /// Warns through colour when a metric approaches saturation.
    ///
    /// Drawn from the accents' own saturation and brightness rather than the
    /// system's green, orange and red, which are louder than anything else in
    /// the panel and made a healthy dot the brightest thing on screen.
    static func statusTint(_ fraction: Double) -> Color {
        let hue: Double = switch fraction {
        case ..<0.7: 0.37
        case ..<0.88: 0.09
        default: 0.0
        }
        return Color(hue: hue, saturation: accentSaturation + 0.08, brightness: accentBrightness)
    }
}

/// The handful of text styles every surface draws with.
///
/// The views used to carry their own point sizes — ten of them, from 9 to 28 —
/// so two cards that meant the same thing could set it a size apart.
enum Typography {
    /// Secondary facts under a value: a detail's label, the uptime.
    static let caption = Font.system(size: 10)
    /// Running text: a metric's caption, an empty state.
    static let body = Font.system(size: 11)
    /// Names in a list, buttons, short labels.
    static let label = Font.system(size: 11, weight: .medium)
    /// The quiet title at the head of a card.
    static let heading = Font.system(size: 12, weight: .medium)
    /// A number that is the point of its row.
    static let value = Font.system(size: 12, weight: .semibold)
    /// The app's name, a chip's name.
    static let title = Font.system(size: 13, weight: .semibold)
    /// The one big number on a dashboard card.
    static let display = Font.system(size: 28, weight: .medium)
    /// The glyph inside an icon chip.
    static let chipIcon = Font.system(size: 11, weight: .semibold)
}
