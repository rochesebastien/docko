import Foundation
import ServiceManagement

/// Enregistrement de Docko comme élément d'ouverture de session (macOS 13+).
enum LoginItemService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Vrai quand macOS attend que l'utilisateur autorise l'élément dans Réglages Système.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Réaligne l'état macOS sur la préférence enregistrée : utile si l'app a été
    /// déplacée ou si l'enregistrement a été perdu entre deux lancements.
    static func sync(with preference: Bool) {
        guard preference, !isEnabled, !requiresApproval else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("Docko: impossible de réenregistrer le lancement au démarrage: \(error)")
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
