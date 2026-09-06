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

/// Réglages d'apparence du Dock (taille, agrandissement, masquage, position…),
/// mémorisés tels quels sous leurs clés `com.apple.dock`. Une clé absente signifie
/// « valeur par défaut de macOS » et sera retirée à l'application.
struct DockSettings: Codable, Hashable {
    enum Value: Hashable {
        case bool(Bool)
        case number(Double)
        case string(String)
    }

    var values: [String: Value] = [:]

    var isEmpty: Bool { values.isEmpty }

    func bool(_ key: String) -> Bool? {
        if case .bool(let b)? = values[key] { return b }
        if case .number(let n)? = values[key] { return n != 0 }
        return nil
    }

    func number(_ key: String) -> Double? {
        if case .number(let n)? = values[key] { return n }
        return nil
    }

    func string(_ key: String) -> String? {
        if case .string(let s)? = values[key] { return s }
        return nil
    }

    /// Résumé lisible : « Taille 48 · Agrandissement 128 · Masquage auto · En bas ».
    var summary: String {
        var parts: [String] = []
        if let size = number("tilesize") { parts.append("Taille \(Int(size.rounded()))") }
        if bool("magnification") == true {
            let large = number("largesize").map { " \(Int($0.rounded()))" } ?? ""
            parts.append("Agrandissement" + large)
        } else {
            parts.append("Sans agrandissement")
        }
        parts.append(bool("autohide") == true ? "Masquage auto" : "Toujours visible")
        switch string("orientation") {
        case "left": parts.append("À gauche")
        case "right": parts.append("À droite")
        default: parts.append("En bas")
        }
        switch string("mineffect") {
        case "scale": parts.append("Effet échelle")
        case "suck": parts.append("Effet aspiration")
        default: parts.append("Effet génie")
        }
        if bool("show-recents") == false { parts.append("Sans apps récentes") }
        if bool("minimize-to-application") == true { parts.append("Réduction dans l'icône") }
        return parts.joined(separator: " · ")
    }
}

extension DockSettings.Value: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        self = .string(try c.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        }
    }
}

/// Un profil de Dock : un nom, une couleur, la liste ordonnée des éléments,
/// et optionnellement les réglages d'apparence du Dock.
struct DockProfile: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var colorHex: String = DockProfile.defaultColors[0]
    var items: [DockItem] = []
    /// nil = le profil ne touche pas aux réglages du Dock.
    var dockSettings: DockSettings? = nil
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
