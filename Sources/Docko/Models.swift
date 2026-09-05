import Foundation

/// Un élément du Dock : une application épinglée ou un espaceur.
struct DockItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case app
        case spacer
        case smallSpacer
    }

    var id: UUID = UUID()
    var kind: Kind
    var path: String?
    var label: String?
    var bundleID: String?

    static func app(path: String, label: String? = nil, bundleID: String? = nil) -> DockItem {
        let url = URL(fileURLWithPath: path)
        let resolvedLabel = label ?? url.deletingPathExtension().lastPathComponent
        let resolvedBundleID = bundleID ?? Bundle(url: url)?.bundleIdentifier
        return DockItem(kind: .app, path: path, label: resolvedLabel, bundleID: resolvedBundleID)
    }

    static func spacer(small: Bool) -> DockItem {
        DockItem(kind: small ? .smallSpacer : .spacer)
    }

    var isSpacer: Bool { kind != .app }

    var displayName: String {
        switch kind {
        case .app:
            if let label, !label.isEmpty { return label }
            if let path { return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
            return "Application"
        case .spacer:
            return "Espace"
        case .smallSpacer:
            return "Petit espace"
        }
    }

    /// Vrai pour les espaceurs, et pour les apps dont le bundle existe encore sur le disque.
    var existsOnDisk: Bool {
        guard kind == .app, let path else { return true }
        return FileManager.default.fileExists(atPath: path)
    }
}

/// Un profil de Dock : un nom, une couleur, et la liste ordonnée des éléments.
struct DockProfile: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var colorHex: String = DockProfile.defaultColors[0]
    var items: [DockItem] = []
    var createdAt: Date = Date()
    /// Touche pressée après le déclencheur. nil = chiffre selon la position dans la liste.
    var hotkey: Shortcut? = nil

    static let defaultColors = [
        "#4A90E2", "#50C878", "#F5A623", "#E94E77", "#9B59B6", "#1ABC9C", "#E67E22", "#7F8C8D",
    ]

    static func nextColor(after profiles: [DockProfile]) -> String {
        defaultColors[profiles.count % defaultColors.count]
    }
}
