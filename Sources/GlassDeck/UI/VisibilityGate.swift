import AppKit
import SwiftUI

/// Ties a flag to a view's time on screen, so a body can stop reading live
/// values while nobody can see them.
///
/// SwiftUI keeps the menu bar panel's view tree alive after the panel closes, and
/// a body that goes on reading the snapshot goes on being invalidated at the
/// sampling cadence — which invalidates the hosting view's size constraints, and
/// that relays out the whole tree on every display cycle, into a window that is
/// no longer on screen. Measured on an M1: a launch that never opened the
/// dashboard sat at 0.2% of a core, and opening it once left the app at 30% for
/// the rest of the session, with the window closed.
///
/// Gating what the body *reads* is what stops it: with no observable property
/// left to change, the animations settle where they are and the redraws stop.
///
/// The signal for that gate has to come from AppKit. `onDisappear` looks like
/// the obvious hook and is not one — for a window the app keeps a reference to,
/// so that closing only orders it out, it never fires at all. The panel was the
/// only surface that ever looked well behaved, and only because nothing retains
/// its window: closing it deallocates the tree, which is why the bug hid there.
/// The window itself does know, so ask it.
struct VisibilityGate: ViewModifier {
    @Binding var isOnScreen: Bool
    /// Runs while the live values can still be read, so the view can hold on to
    /// its last reading and have something to draw the moment it comes back.
    let beforeHiding: () -> Void

    func body(content: Content) -> some View {
        content
            .background(WindowVisibilityReader(onChange: update).frame(width: 0, height: 0))
            // Kept for the case the window notifications cannot cover: a tree
            // torn down without its window ever closing.
            .onDisappear { update(false) }
    }

    private func update(_ visible: Bool) {
        guard visible != isOnScreen else { return }
        if !visible { beforeHiding() }
        isOnScreen = visible
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

/// Reports whether the window hosting this view is actually on screen.
///
/// Two conditions, because either one alone is a way to be invisible: `isVisible`
/// covers a window that has been ordered out — which is what closing one of
/// GlassDeck's windows does — and the occlusion state covers one that is still
/// ordered in but completely buried, on another Space, or in a hidden app.
private struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.onChange = onChange
        return probe
    }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.onChange = onChange
    }

    final class Probe: NSView {
        var onChange: ((Bool) -> Void)?
        private weak var observed: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            if let observed { center.removeObserver(self, name: nil, object: observed) }
            observed = window

            guard let window else { return report(false) }
            for name in [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.willCloseNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
            ] {
                center.addObserver(self, selector: #selector(windowChanged), name: name, object: window)
            }
            report(isOnScreen(window))
        }

        @objc private func windowChanged(_ note: Notification) {
            guard let window = observed else { return report(false) }
            // `willClose` is posted while the window still reports itself
            // visible, so it has to be taken at its word rather than re-read.
            report(note.name == NSWindow.willCloseNotification ? false : isOnScreen(window))
        }

        private func isOnScreen(_ window: NSWindow) -> Bool {
            window.isVisible && window.occlusionState.contains(.visible)
        }

        /// Handed back a turn later: the first reading is taken during layout,
        /// and driving a `@State` change from inside a view update is exactly
        /// what SwiftUI warns about.
        private func report(_ visible: Bool) {
            DispatchQueue.main.async { [weak self] in self?.onChange?(visible) }
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
