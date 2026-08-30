import Foundation
import ServiceManagement

/// Wraps `SMAppService` so the settings toggle can read and write "open at login"
/// without the UI having to care about the service's error handling.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// - Returns: `true` when the requested state was reached.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            // Registration fails for unbundled or unsigned builds (e.g. `swift run`);
            // that is expected during development and must not crash the app.
            NSLog("GlassDeck: login item update failed – \(error.localizedDescription)")
            return false
        }
    }
}
