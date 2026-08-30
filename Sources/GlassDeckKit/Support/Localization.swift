import Foundation

/// Localised text owned by the kit.
///
/// The kit ships its own string table because the words it produces — "charging",
/// "on battery", "idle" — are read by the user, not just consumed by the app.
/// Keys are explicit so the tables stay stable when the English wording is edited,
/// which is also why this goes through `NSLocalizedString`: the `String(localized:)`
/// initialisers only accept literal keys.
enum L {
    static func t(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, bundle: .module, value: fallback, comment: "")
    }

    /// Formats a localised template, e.g. `"range %1$lld–%2$lld rpm"`.
    static func t(_ key: String, _ fallback: String, _ arguments: any CVarArg...) -> String {
        String(format: t(key, fallback), arguments: arguments)
    }
}
