import SwiftUI

/// The pieces the settings window is built from: grouped cards of rows, each
/// row headed by a dark icon tile, with the control on the trailing edge.
///
/// A window of its own vocabulary rather than a grouped `Form`: the form put
/// every setting at the same weight in one long column, and there was no room
/// in it to say what a setting costs — which, for a system monitor, is often
/// the thing worth knowing before switching it on.
enum SettingsMetrics {
    static let sidebarWidth: CGFloat = 214
    static let windowSize = CGSize(width: 800, height: 560)
    /// Heights the embedded lists are given, one per row: a list inside the
    /// scrolling page cannot size itself to its rows.
    static let metricRowHeight: CGFloat = 45
    static let zoneRowHeight: CGFloat = 38
}

extension View {
    /// The fill and shape of every settings card.
    func settingsCardBackground() -> some View {
        background(Theme.Settings.card, in: RoundedRectangle(cornerRadius: Theme.Settings.cardRadius, style: .continuous))
    }

    /// A `List` laid into a card: plain, transparent, not scrolling on its own
    /// — the page does — and as tall as its rows. Used where rows must be
    /// draggable, since only a list carries `onMove` on macOS.
    func settingsEmbeddedList(rows: Int, rowHeight: CGFloat) -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: CGFloat(rows) * rowHeight)
            .padding(.horizontal, 4)
            .settingsCardBackground()
    }
}

/// A rounded card the rows of one section sit in.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsCardBackground()
    }
}

/// The bold title above a card.
struct SettingsSectionHeader: View {
    let title: Text

    init(_ title: Text) { self.title = title }

    var body: some View {
        title
            .font(.system(size: 14, weight: .semibold))
            .padding(.top, 10)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The quiet sentence under a card.
struct SettingsFootnote: View {
    let text: Text

    init(_ text: Text) { self.text = text }

    var body: some View {
        text
            .font(Typography.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One setting: icon tile, title with an optional cost tag, a line of
/// explanation, and the control.
struct SettingsRow<Control: View>: View {
    let symbol: String
    let title: Text
    var subtitle: Text?
    /// What the setting costs or asks for — "SMC, cached 3 s", "Asks for
    /// permission" — shown as a pill beside the title.
    var tag: Text?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 10) {
            SettingsIconTile(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    title.font(.system(size: 13))
                    if let tag { SettingsTag(text: tag) }
                }
                if let subtitle {
                    subtitle
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// The hairline between two rows of a card.
struct SettingsRowDivider: View {
    var body: some View {
        Divider().padding(.leading, 38)
    }
}

/// The dark rounded square that heads every row, the device System Settings
/// uses to make a list scannable by shape before it is read.
struct SettingsIconTile: View {
    let symbol: String

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.black)
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

struct SettingsTag: View {
    let text: Text

    var body: some View {
        text
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Theme.Settings.pill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// The selector at the head of a page with more than one part: a row of glass
/// buttons, the selected one prominent.
struct SettingsSegments<Value: Hashable>: View {
    let options: [(value: Value, title: Text)]
    @Binding var selection: Value

    var body: some View {
        GlassStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    let isSelected = option.value == selection
                    Button { selection = option.value } label: {
                        option.title.padding(.horizontal, 4)
                    }
                    .glassButton(prominent: isSelected)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
        }
    }
}

/// The card that opens every page: a title or the segments, what the page is
/// for, and — where there is one — a summary line with the page's actions.
struct SettingsIntroCard<Header: View, Footer: View>: View {
    @ViewBuilder var header: Header
    let text: Text
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.bottom, 10)
            Divider()
            text
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)
            if Footer.self != EmptyView.self {
                Divider()
                HStack(spacing: 8) { footer }
                    .font(.system(size: 12))
                    .padding(.top, 10)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCardBackground()
    }
}

extension SettingsIntroCard where Footer == EmptyView {
    init(@ViewBuilder header: () -> Header, text: Text) {
        self.init(header: header, text: text, footer: { EmptyView() })
    }
}

extension View {
    /// A switch on a settings row: the app's glass switch without its label,
    /// since the row already says what it is. VoiceOver still reads the label.
    func settingsSwitch() -> some View {
        toggleStyle(GlassSwitchStyle(showsLabel: false))
    }
}
