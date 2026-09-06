import AppKit

/// Position initiale de l'icône dans la barre des menus.
///
/// Les outils qui replient la barre (Hidden Bar, par exemple) élargissent leur séparateur pour
/// pousser hors écran tout ce qui se trouve à sa gauche — dont chaque nouvelle icône, qui arrive
/// justement là. Au premier lancement, on demande donc à AppKit de placer Docko juste à droite
/// de leur bouton « déplier », dans la zone visible. L'utilisateur peut ensuite la déplacer
/// avec ⌘-glisser ; AppKit mémorise sa position.
enum MenuBarPlacement {
    static let autosaveName = "Docko"

    private static var preferenceKey: String { "NSStatusItem Preferred Position \(autosaveName)" }

    static func seedPreferredPositionIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: preferenceKey) == nil else { return }
        guard let anchor = collapserAnchorPosition() else { return }
        // Les positions se comptent depuis le bord droit de l'écran : plus petit = plus à droite.
        defaults.set(max(anchor - 1, 0), forKey: preferenceKey)
    }

    /// Position du bouton « déplier » d'un outil de repli connu, s'il est installé.
    private static func collapserAnchorPosition() -> Double? {
        let candidates: [(domain: String, key: String)] = [
            ("com.dwarvesv.minimalbar", "NSStatusItem Preferred Position hiddenbar_expandcollapse"), // Hidden Bar
        ]
        for candidate in candidates {
            if let value = preference(candidate.key, inDomain: candidate.domain) {
                return value
            }
        }
        return nil
    }

    /// Lit une préférence d'une autre app. Les apps sandboxées (App Store) rangent la leur dans
    /// leur conteneur, hors de portée de `UserDefaults(suiteName:)` : on lit le fichier directement.
    private static func preference(_ key: String, inDomain domain: String) -> Double? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let files = [
            home.appendingPathComponent("Library/Containers/\(domain)/Data/Library/Preferences/\(domain).plist"),
            home.appendingPathComponent("Library/Preferences/\(domain).plist"),
        ]
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let value = plist[key] as? NSNumber
            else { continue }
            return value.doubleValue
        }
        return nil
    }
}
