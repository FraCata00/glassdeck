import Foundation
import IOKit.ps

/// Calls back on the main thread whenever macOS reports a change to any power
/// source: the adapter going in or out, charging starting or stopping, the
/// charge level moving.
///
/// Polling alone left the battery chip up to a few seconds behind the cable,
/// which is exactly the moment somebody is looking at it.
///
/// The run-loop source holds an unretained pointer back to the observer, so
/// every `start()` has to be balanced by a `stop()` before the observer goes.
@MainActor
final class PowerSourceObserver {
    private let onChange: @MainActor () -> Void
    private var source: CFRunLoopSource?

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard source == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            // The source is added to the main run loop, so this is already
            // running on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<PowerSourceObserver>.fromOpaque(context).takeUnretainedValue().onChange()
            }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue()
        else { return }
        // Common modes, so a notification is not held back while a menu or the
        // Touch Bar is tracking.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
    }

    func stop() {
        guard let source else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = nil
    }
}
