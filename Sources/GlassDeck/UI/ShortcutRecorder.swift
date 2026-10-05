import AppKit
import Carbon.HIToolbox
import GlassDeckKit
import SwiftUI

/// A field that records a keyboard shortcut: click it, then press the keys.
///
/// Escape cancels. A combination with no ⌘, ⌥ or ⌃ is refused with a beep —
/// registered system-wide, it would take a key away from typing everywhere.
struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut?
    /// Told when recording starts and stops, so the shortcut already in place
    /// can be set aside: a registered hot key never reaches the app's own
    /// event stream, so pressing it again could not otherwise be recorded.
    var onRecordingChange: (Bool) -> Void = { _ in }

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if isRecording { stop() } else { start() }
            } label: {
                Text(title)
                    .monospacedDigit()
                    .frame(minWidth: 90)
            }
            if shortcut != nil, !isRecording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(String(localized: "Turn the shortcut off"))
            }
        }
        .onDisappear(perform: stop)
    }

    private var title: String {
        if isRecording { return String(localized: "Type the shortcut…") }
        return shortcut?.displayName ?? String(localized: "No shortcut")
    }

    private func start() {
        guard !isRecording else { return }
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            record(event)
            return nil
        }
    }

    private func stop() {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        onRecordingChange(false)
    }

    private func record(_ event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape { return stop() }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let candidate = KeyShortcut(
            keyCode: Int(event.keyCode),
            key: Self.label(for: event),
            command: flags.contains(.command),
            option: flags.contains(.option),
            control: flags.contains(.control),
            shift: flags.contains(.shift)
        )
        guard candidate.isUsable, !candidate.key.isEmpty else { return NSSound.beep() }
        shortcut = candidate
        stop()
    }

    /// What to print for the key. Letters and digits come from the layout in
    /// use; keys that type nothing printable get the names menus give them.
    private static func label(for event: NSEvent) -> String {
        let named: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = named[Int(event.keyCode)] { return name }
        let characters = event.charactersIgnoringModifiers ?? ""
        // Function keys type characters from the private-use area, which draw
        // as nothing.
        guard let scalar = characters.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              !(0xF700...0xF8FF).contains(scalar.value)
        else { return "" }
        return characters
    }
}
