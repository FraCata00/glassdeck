import SwiftUI

/// Ties a flag to a view's time on screen, so a body can stop reading live
/// values while nobody can see them.
///
/// SwiftUI keeps the menu bar panel's view tree alive after the panel closes.
/// `onDisappear` does run — the process scan has relied on it since the list was
/// added — but the tree is not torn down, so a body that goes on reading the
/// snapshot goes on being invalidated four times a minute, and the gauges'
/// springs and the glass effect go on animating into a window that is no longer
/// on screen. Measured on an M1: a launch that never opened the panel sat at
/// 0.2% of a core, and opening it once left the app at 33% for the rest of the
/// session, with the panel closed.
///
/// Gating what the body *reads* is what stops it: with no observable property
/// left to change, the animations settle where they are and the redraws stop.
struct VisibilityGate: ViewModifier {
    @Binding var isOnScreen: Bool
    /// Runs while the live values can still be read, so the view can hold on to
    /// its last reading and have something to draw the moment it comes back.
    let beforeHiding: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { isOnScreen = true }
            .onDisappear {
                beforeHiding()
                isOnScreen = false
            }
    }
}

extension View {
    func tracksVisibility(
        _ isOnScreen: Binding<Bool>,
        beforeHiding: @escaping () -> Void = {}
    ) -> some View {
        modifier(VisibilityGate(isOnScreen: isOnScreen, beforeHiding: beforeHiding))
    }
}
