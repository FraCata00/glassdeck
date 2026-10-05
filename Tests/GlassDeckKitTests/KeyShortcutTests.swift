import Carbon.HIToolbox
import Foundation
import Testing
@testable import GlassDeckKit

@Suite("Keyboard shortcut")
struct KeyShortcutTests {
    @Test("The default hands the bar over with ⌃⌥⌘T")
    func defaultShortcut() {
        let shortcut = KeyShortcut.defaultYield
        #expect(shortcut.keyCode == kVK_ANSI_T)
        #expect(shortcut.displayName == "⌃⌥⌘T")
    }

    @Test("Modifiers are spelled in the order the menus use")
    func displayOrder() {
        let shortcut = KeyShortcut(keyCode: kVK_ANSI_K, key: "k", command: true, option: true, control: true, shift: true)
        #expect(shortcut.displayName == "⌃⌥⇧⌘K")
    }

    @Test("Carbon receives the modifiers that were pressed and no others")
    func carbonModifiers() {
        let shortcut = KeyShortcut(keyCode: kVK_ANSI_T, key: "t", command: true, option: false, control: true, shift: false)
        #expect(shortcut.carbonModifiers == cmdKey | controlKey)
    }

    @Test("Shift alone is not enough: it would swallow a capital letter")
    func needsModifier() {
        #expect(!KeyShortcut(keyCode: kVK_ANSI_T, key: "t", command: false, option: false, control: false, shift: true).isUsable)
        #expect(!KeyShortcut(keyCode: kVK_ANSI_T, key: "t", command: false, option: false, control: false, shift: false).isUsable)
        #expect(KeyShortcut(keyCode: kVK_ANSI_T, key: "t", command: false, option: true, control: false, shift: true).isUsable)
    }

    @Test("A shortcut survives being stored, and so does turning it off")
    func roundTrip() throws {
        let stored = try JSONEncoder().encode(KeyShortcut?.some(.defaultYield))
        #expect(try JSONDecoder().decode(KeyShortcut?.self, from: stored) == .defaultYield)
        let off = try JSONEncoder().encode(KeyShortcut?.none)
        #expect(try JSONDecoder().decode(KeyShortcut?.self, from: off) == nil)
    }
}
