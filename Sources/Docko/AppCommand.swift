import Foundation

/// Les commandes de l'application auxquelles on peut associer un raccourci clavier global.
/// L'ordre de `allCases` est celui des réglages et sert d'identifiant Carbon stable.
enum AppCommand: String, CaseIterable, Codable, Identifiable {
    case openManager
    case captureCurrentDock
    case updateActiveProfile
    case applyNextProfile
    case openDockSettings
    case restartDock
    case quit

    var id: String { rawValue }

    /// Libellé tel qu'il apparaît dans le menu et les réglages.
    var title: String {
        switch self {
        case .openManager: return "Gérer les profils…"
        case .captureCurrentDock: return "Enregistrer le Dock actuel comme nouveau profil…"
        case .updateActiveProfile: return "Mettre à jour le profil actif depuis le Dock actuel"
        case .applyNextProfile: return "Profil suivant"
        case .openDockSettings: return "Réglages du Dock…"
        case .restartDock: return "Relancer le Dock"
        case .quit: return "Quitter Docko"
        }
    }

    /// Libellé court pour la liste des raccourcis.
    var shortTitle: String {
        switch self {
        case .openManager: return "Gérer les profils"
        case .captureCurrentDock: return "Enregistrer le Dock actuel"
        case .updateActiveProfile: return "Mettre à jour le profil actif"
        case .applyNextProfile: return "Profil suivant"
        case .openDockSettings: return "Réglages du Dock"
        case .restartDock: return "Relancer le Dock"
        case .quit: return "Quitter Docko"
        }
    }

    var symbol: String {
        switch self {
        case .openManager: return "rectangle.stack"
        case .captureCurrentDock: return "plus.circle"
        case .updateActiveProfile: return "arrow.triangle.2.circlepath"
        case .applyNextProfile: return "arrow.right.circle"
        case .openDockSettings: return "dock.rectangle"
        case .restartDock: return "arrow.clockwise"
        case .quit: return "xmark.square"
        }
    }
}
