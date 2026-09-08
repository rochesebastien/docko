import AppKit
import Carbon

/// Une touche avec ses modificateurs, affichable et convertible pour Carbon.
struct Shortcut: Codable, Hashable {
    /// Code de touche virtuel (kVK_*).
    var keyCode: UInt32
    /// `NSEvent.ModifierFlags` restreint à ⌘ ⇧ ⌥ ⌃.
    var modifiers: UInt32
    /// Libellé de la touche seule, par exemple « D » ou « 1 ».
    var keyLabel: String

    static let relevantFlags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    /// Vrai si au moins un modificateur est présent : condition pour un raccourci global.
    var hasModifiers: Bool { !flags.isEmpty }

    var flags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(modifiers)).intersection(Shortcut.relevantFlags)
    }

    /// Modificateurs au format Carbon pour RegisterEventHotKey.
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    /// Représentation lisible, par exemple « ⌘D » ou « ⌃⇧1 ».
    var display: String {
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        return symbols + keyLabel
    }

    /// Même touche et mêmes modificateurs : deux raccourcis qui se marcheraient dessus.
    func collides(with other: Shortcut) -> Bool {
        keyCode == other.keyCode && flags == other.flags
    }

    // MARK: - Enregistrement depuis un NSEvent

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    init(event: NSEvent) {
        let flags = event.modifierFlags.intersection(Shortcut.relevantFlags)
        self.init(
            keyCode: UInt32(event.keyCode),
            modifiers: UInt32(flags.rawValue),
            keyLabel: Shortcut.label(for: event)
        )
    }

    private static let specialLabels: [Int: String] = [
        kVK_Space: "Espace", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    static func label(for event: NSEvent) -> String {
        if let special = specialLabels[Int(event.keyCode)] { return special }
        let chars = event.charactersIgnoringModifiers ?? ""
        let cleaned = chars.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "?" : cleaned
    }
}
