import Carbon.HIToolbox
import GlassDeckKit

/// A system-wide keyboard shortcut.
///
/// Registered through Carbon rather than an `NSEvent` monitor: a hot key is
/// delivered to the app that registered it whoever is frontmost, and needs no
/// Accessibility permission to do so.
@MainActor
final class GlobalHotKey {
    /// The combination listened for; `nil` listens for nothing. Changing it
    /// takes effect straight away.
    var shortcut: KeyShortcut? {
        didSet {
            guard shortcut != oldValue else { return }
            unregisterKey()
            registerKey()
        }
    }

    private let action: () -> Void
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    private func registerKey() {
        guard let shortcut, shortcut.isUsable else { return }
        installHandler()
        // 'GDKY' — any signature works, it only has to be ours.
        let identifier = EventHotKeyID(signature: 0x4744_4B59, id: 1)
        RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            UInt32(shortcut.carbonModifiers),
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
    }

    private func unregisterKey() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
    }

    /// The handler stays installed once it is: it only ever hears our own key.
    private func installHandler() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers application-target events on the main thread.
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }
}
