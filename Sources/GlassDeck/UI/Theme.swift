import GlassDeckKit
import SwiftUI

/// Colour and layout constants shared by every surface, so the window, the menu
/// bar glyph and the Touch Bar all speak the same visual language.
enum Theme {
    static let cornerRadius: CGFloat = 20
    static let tileCornerRadius: CGFloat = 16
    static let panelWidth: CGFloat = 396

    /// Accent colour of a metric or a module.
    ///
    /// Saturation is kept well below full: system surfaces on macOS use colour to
    /// identify a thing, not to shout, and neon accents fight the glass material.
    static func accent(_ kind: some Accented) -> Color {
        Color(hue: kind.hue, saturation: 0.62, brightness: 0.92)
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

    /// Warns through colour when a metric approaches saturation.
    static func statusTint(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.7: .green
        case ..<0.88: .orange
        default: .red
        }
    }
}
