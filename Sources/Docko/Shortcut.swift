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

    /// Déclencheur par défaut : ⌘D.
    static let defaultLeader = Shortcut(
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: UInt32(NSEvent.ModifierFlags.command.rawValue),
        keyLabel: "D"
    )

    private static let digitKeyCodes: [Int: Int] = [
        1: kVK_ANSI_1, 2: kVK_ANSI_2, 3: kVK_ANSI_3, 4: kVK_ANSI_4, 5: kVK_ANSI_5,
        6: kVK_ANSI_6, 7: kVK_ANSI_7, 8: kVK_ANSI_8, 9: kVK_ANSI_9,
    ]

    /// Touche chiffre sans modificateur, pour les profils 1 à 9.
    static func digit(_ n: Int) -> Shortcut? {
        guard let code = digitKeyCodes[n] else { return nil }
        return Shortcut(keyCode: UInt32(code), modifiers: 0, keyLabel: String(n))
    }

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
