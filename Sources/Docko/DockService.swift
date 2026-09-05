import Foundation
import CoreFoundation

enum DockServiceError: LocalizedError {
    case synchronizeFailed
    case restartFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .synchronizeFailed:
            return "Impossible d'écrire les préférences du Dock (com.apple.dock)."
        case .restartFailed(let status):
            return "Le redémarrage du Dock a échoué (killall a renvoyé \(status))."
        }
    }
}

/// Lecture et écriture de la section « persistent-apps » du Dock.
///
/// Les dossiers (« persistent-others »), les apps récentes et les réglages du Dock
/// (taille, position, agrandissement…) ne sont jamais touchés.
enum DockService {
    private static let domain = "com.apple.dock" as CFString
    private static let persistentAppsKey = "persistent-apps" as CFString

    /// Les éléments actuellement épinglés dans le Dock.
    static func currentItems() -> [DockItem] {
        guard let raw = CFPreferencesCopyAppValue(persistentAppsKey, domain) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap(item(from:))
    }

    /// Remplace les apps épinglées par `items` puis relance le Dock.
    static func apply(_ items: [DockItem]) throws {
        let plist = items.map(dictionary(for:)) as CFArray
        CFPreferencesSetAppValue(persistentAppsKey, plist, domain)
        guard CFPreferencesAppSynchronize(domain) else {
            throw DockServiceError.synchronizeFailed
        }
        try restartDock()
    }

    static func restartDock() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DockServiceError.restartFailed(process.terminationStatus)
        }
    }

    // MARK: - Conversion plist <-> DockItem

    private static func item(from dictionary: [String: Any]) -> DockItem? {
        let tileType = dictionary["tile-type"] as? String ?? "file-tile"
        switch tileType {
        case "spacer-tile":
            return .spacer(small: false)
        case "small-spacer-tile":
            return .spacer(small: true)
        case "file-tile":
            guard let tileData = dictionary["tile-data"] as? [String: Any],
                  let fileData = tileData["file-data"] as? [String: Any],
                  let urlString = fileData["_CFURLString"] as? String
            else { return nil }

            let path: String
            if urlString.hasPrefix("file://"), let url = URL(string: urlString) {
                path = url.path
            } else {
                path = urlString
            }
            let label = tileData["file-label"] as? String
            let bundleID = tileData["bundle-identifier"] as? String
            return .app(path: path, label: label, bundleID: bundleID)
        default:
            // Types inconnus (ils n'apparaissent normalement que dans persistent-others).
            return nil
        }
    }

    private static func dictionary(for item: DockItem) -> [String: Any] {
        switch item.kind {
        case .spacer:
            return ["tile-type": "spacer-tile", "tile-data": [String: Any]()]
        case .smallSpacer:
            return ["tile-type": "small-spacer-tile", "tile-data": [String: Any]()]
        case .app:
            let path = item.path ?? ""
            var tileData: [String: Any] = [
                "file-data": [
                    "_CFURLString": URL(fileURLWithPath: path).absoluteString,
                    "_CFURLStringType": 15,
                ],
                "file-label": item.displayName,
                "file-type": 41,
            ]
            if let bundleID = item.bundleID {
                tileData["bundle-identifier"] = bundleID
            }
            return ["tile-type": "file-tile", "tile-data": tileData]
        }
    }
}
