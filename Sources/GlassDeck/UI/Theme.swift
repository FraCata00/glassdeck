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
        switch StrainBand(strain: fraction) {
        case .calm: calmTint
        case .elevated: elevatedTint
        case .high: highTint
        }
    }

    /// The same tint for the surfaces drawn in AppKit, by band.
    static func nsStatusTint(_ band: StrainBand) -> NSColor {
        switch band {
        case .calm: nsCalmTint
        case .elevated: nsElevatedTint
        case .high: nsHighTint
        }
    }

    // Built once: the dots and the signal style ask for these on every sample.
    private static let nsCalmTint = statusColour(hue: 0.37)
    private static let nsElevatedTint = statusColour(hue: 0.09)
    private static let nsHighTint = statusColour(hue: 0.0)
    private static let calmTint = Color(nsColor: nsCalmTint)
    private static let elevatedTint = Color(nsColor: nsElevatedTint)
    private static let highTint = Color(nsColor: nsHighTint)

    private static func statusColour(hue: Double) -> NSColor {
        NSColor(hue: hue, saturation: accentSaturation + 0.08, brightness: accentBrightness, alpha: 1)
    }

    /// The Touch Bar terminal style's one colour: the amber of an old phosphor
    /// screen, readable on the black panel without competing with the accents.
    static let nsPhosphor = NSColor(red: 1, green: 0.69, blue: 0, alpha: 1)

    /// The translucent fills the Touch Bar draws on its black panel.
    enum TouchBar {
        /// Behind a chip.
        static let chip = NSColor.white.withAlphaComponent(0.08)
        /// The unlit part of a meter or a ring.
        static let track = NSColor.white.withAlphaComponent(0.12)
        /// The rule between cells in the open styles.
        static let hairline = NSColor.white.withAlphaComponent(0.14)
        static let chipRadius: CGFloat = 7
    }

    /// The settings window's surfaces.
    enum Settings {
        static let cardRadius: CGFloat = 10
        /// Behind a card of rows.
        static let card = Color.primary.opacity(0.05)
        /// Behind a pill: a tag, the segment track, an unfilled button.
        static let pill = Color.primary.opacity(0.08)
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
