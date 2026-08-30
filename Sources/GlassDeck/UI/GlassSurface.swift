import SwiftUI

/// Applies the macOS 26 Liquid Glass material, falling back to a hand-tuned
/// vibrant material stack on older systems so the layout never changes shape.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.tileCornerRadius
    var isInteractive = false
    var isTinted: Color?

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let isTinted { glass = glass.tint(isTinted) }
        if isInteractive { glass = glass.interactive() }
        return glass
    }
}

/// Groups glass views so their shapes blend into one another when they move or
/// resize. Degrades to a plain stack before macOS 26.
struct GlassStack<Content: View>: View {
    var spacing: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

extension View {
    /// Wraps the view in a Liquid Glass surface.
    func glassSurface(
        cornerRadius: CGFloat = Theme.tileCornerRadius,
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, isInteractive: interactive, isTinted: tint))
    }

    /// Liquid Glass button styling with a pre-26 fallback.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            buttonStyle(.bordered)
        }
    }

    /// Ties a view into the container's morph animations when glass is available.
    @ViewBuilder
    func glassMorph(id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}
