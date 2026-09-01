import SwiftUI

/// A switch drawn in Liquid Glass, so the settings window speaks the same
/// material as the panel it configures.
///
/// The system's own `.switch` is an opaque control: beside the glass surfaces
/// everywhere else in the app it reads as a piece of a different toolkit. This
/// keeps the system's shape and behaviour — a capsule track, a knob that slides,
/// the accent colour for on — and swaps only the paint, with the same
/// pre-macOS 26 fallback the rest of the app carries so nothing moves on an
/// older system.
struct GlassSwitchStyle: ToggleStyle {
    private static let width: CGFloat = 42
    private static let height: CGFloat = 24
    private static let knobInset: CGFloat = 2.5

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.22)) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: 8) {
                configuration.label
                Spacer(minLength: 8)
                track(isOn: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The knob and the track are shapes, not a control: without this a
        // screen reader would find a button with no state to read out.
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }

    private func track(isOn: Bool) -> some View {
        glass(isOn: isOn)
            .frame(width: Self.width, height: Self.height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .padding(Self.knobInset)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .frame(width: Self.height, height: Self.height)
            }
            .animation(.smooth(duration: 0.22), value: isOn)
    }

    @ViewBuilder
    private func glass(isOn: Bool) -> some View {
        if #available(macOS 26.0, *) {
            // Tinted rather than filled: the accent still says "on" at a glance,
            // and what is behind the track still shows through it.
            Color.clear.glassEffect(
                isOn ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                in: .capsule
            )
        } else {
            Capsule()
                .fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.8))
        }
    }
}

extension ToggleStyle where Self == GlassSwitchStyle {
    /// A switch in the app's own material. Use it wherever a `Toggle` is shown.
    static var glass: GlassSwitchStyle { GlassSwitchStyle() }
}
