import SwiftUI

enum SettingsMetrics {
    static let sidebarWidth: CGFloat = 230
    static let windowSize = CGSize(width: 860, height: 640)
    /// Below this the style grid squeezes the panel previews until their
    /// names are cut short.
    static let minimumSize = CGSize(width: 820, height: 480)
}

/// The coloured rounded square System Settings heads each page with: in the
/// sidebar beside the page's name, and large above its title. It makes a list
/// of pages scannable by colour before a word of it is read.
struct SettingsIcon: View {
    let page: SettingsPage
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(page.tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: page.symbol)
                    .font(.system(size: size * 0.55, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}
