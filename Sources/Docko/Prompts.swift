import AppKit

/// Petites boîtes de dialogue AppKit, utilisables depuis le menu comme depuis SwiftUI.
enum Prompts {
    /// Demande un nom. Renvoie nil si l'utilisateur annule ou laisse le champ vide.
    static func askForName(title: String, message: String? = nil, defaultName: String, confirmTitle: String = "Enregistrer") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        if let message { alert.informativeText = message }
        alert.alertStyle = .informational
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Annuler")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultName
        field.placeholderString = "Nom du profil"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    static func showError(_ error: Error, title: String = "Docko") {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    static func confirm(title: String, message: String, confirmTitle: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Annuler")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
