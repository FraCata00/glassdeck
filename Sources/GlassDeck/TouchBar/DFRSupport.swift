import AppKit

/// Thin, defensive bridge to the two DFRFoundation entry points that let a regular
/// app place a persistent item in the Touch Bar Control Strip.
///
/// These symbols are not part of the public SDK, so everything is resolved through
/// `dlsym` at runtime: on a Mac without a Touch Bar — or on a future macOS that
/// drops them — every call here degrades to a no-op instead of failing to launch.
enum DFRSupport {
    // Immutable process-wide handles: `nonisolated(unsafe)` states that these are
    // never mutated after the first access, which `dlopen`/`dlsym` guarantee.
    nonisolated(unsafe) private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation",
        RTLD_NOW
    )

    private typealias SetControlStripPresence = @convention(c) (CFString, Bool) -> Void
    private typealias SetShowsCloseBox = @convention(c) (Bool) -> Void

    /// True when the running system exposes the Control Strip API at all.
    static var isAvailable: Bool { handle != nil && controlStripPresence != nil }

    nonisolated(unsafe) private static let controlStripPresence: SetControlStripPresence? = symbol(
        "DFRElementSetControlStripPresenceForIdentifier"
    )
    nonisolated(unsafe) private static let showsCloseBox: SetShowsCloseBox? = symbol(
        "DFRSystemModalShowsCloseBoxWhenFrontMost"
    )

    /// Adds or removes the app's button from the Control Strip.
    static func setControlStripPresence(_ identifier: NSTouchBarItem.Identifier, visible: Bool) {
        controlStripPresence?(identifier.rawValue as CFString, visible)
    }

    /// Shows the system close box on the expanded bar while GlassDeck is frontmost.
    static func setSystemModalShowsCloseBox(_ shows: Bool) {
        showsCloseBox?(shows)
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}

/// The private `NSTouchBar` / `NSTouchBarItem` class methods used to own a
/// Control Strip slot, reached through the Objective-C runtime so that a missing
/// selector is a silent no-op rather than a link error.
enum SystemTouchBar {
    private static var itemClass: AnyObject { NSTouchBarItem.self }
    private static var barClass: AnyObject { NSTouchBar.self }

    static func addSystemTrayItem(_ item: NSTouchBarItem) {
        perform(itemClass, "addSystemTrayItem:", item)
    }

    static func removeSystemTrayItem(_ item: NSTouchBarItem) {
        perform(itemClass, "removeSystemTrayItem:", item)
    }

    /// Expands `touchBar` over the full Touch Bar, anchored to our tray item.
    static func presentSystemModal(
        _ touchBar: NSTouchBar,
        identifier: NSTouchBarItem.Identifier,
        placement: Int = 1
    ) {
        let selector = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        guard barClass.responds(to: selector) else { return }
        typealias Present = @convention(c) (AnyObject, Selector, NSTouchBar, Int, NSString) -> Void
        guard let implementation = barClass.method(for: selector) else { return }
        unsafeBitCast(implementation, to: Present.self)(
            barClass, selector, touchBar, placement, identifier.rawValue as NSString
        )
    }

    /// Collapses the expanded bar back into the tray item, handing the Touch Bar
    /// back to the system and the frontmost app.
    ///
    /// This is *not* interchangeable with `dismissSystemModal`: calling both, or
    /// dismissing while a tray item is installed, leaves the Control Strip hidden
    /// until the next app switch.
    static func minimizeSystemModal(_ touchBar: NSTouchBar) {
        perform(barClass, "minimizeSystemModalTouchBar:", touchBar)
    }

    /// Tears the expanded bar down completely. Used when GlassDeck is switched
    /// off or quits, where there is no tray item left to collapse into.
    static func dismissSystemModal(_ touchBar: NSTouchBar) {
        perform(barClass, "dismissSystemModalTouchBar:", touchBar)
    }

    private static func perform(_ target: AnyObject, _ name: String, _ argument: AnyObject) {
        let selector = NSSelectorFromString(name)
        guard target.responds(to: selector) else { return }
        _ = target.perform(selector, with: argument)
    }
}
