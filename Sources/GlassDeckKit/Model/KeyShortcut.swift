import Carbon.HIToolbox
import Foundation

/// A key combination, kept in the terms the Carbon hot key API registers it in.
///
/// The key's label is stored beside its code because a virtual key code names a
/// position on the keyboard, not a letter: working the letter out again later
/// would need the keyboard layout the user had when they recorded it.
public struct KeyShortcut: Codable, Equatable, Sendable {
    public let keyCode: Int
    public let key: String
    public let command: Bool
    public let option: Bool
    public let control: Bool
    public let shift: Bool

    public init(keyCode: Int, key: String, command: Bool, option: Bool, control: Bool, shift: Bool) {
        self.keyCode = keyCode
        self.key = key
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

    /// ⌃⌥⌘T: three modifiers make a clash with another app's shortcut unlikely.
    public static let defaultYield = KeyShortcut(
        keyCode: kVK_ANSI_T,
        key: "t",
        command: true,
        option: true,
        control: true,
        shift: false
    )

    /// A system-wide shortcut with no modifier, or with Shift alone, would take
    /// a key away from typing everywhere.
    public var isUsable: Bool { command || option || control }

    public var carbonModifiers: Int {
        (command ? cmdKey : 0) | (option ? optionKey : 0) | (control ? controlKey : 0) | (shift ? shiftKey : 0)
    }

    /// Spelled the way menus spell shortcuts: ⌃⌥⇧⌘, then the key.
    public var displayName: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key.uppercased()
    }
}
