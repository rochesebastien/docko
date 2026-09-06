import AppKit
import Foundation
import CoreFoundation

enum DockServiceError: LocalizedError {
    case synchronizeFailed
    case restartFailed(Int32)
    case dockDidNotComeBack

    var errorDescription: String? {
        switch self {
        case .synchronizeFailed:
            return "Impossible d'écrire les préférences du Dock (com.apple.dock)."
        case .restartFailed(let status):
            return "Le redémarrage du Dock a échoué (launchctl a renvoyé \(status))."
        case .dockDidNotComeBack:
            return "Le Dock ne s'est pas relancé. Ouvre-le depuis /System/Library/CoreServices/Dock.app ou déconnecte-toi puis reconnecte-toi."
        }
    }
}

/// Lecture et écriture de la section « persistent-apps » du Dock, et optionnellement
/// de ses réglages d'apparence.
///
/// Les dossiers (« persistent-others ») et les apps récentes ne sont jamais touchés.
enum DockService {
    private static let domain = "com.apple.dock" as CFString
    private static let persistentAppsKey = "persistent-apps" as CFString

    /// Clés `com.apple.dock` mémorisées dans un profil quand il inclut les réglages.
    static let settingsKeys: [String] = [
        "tilesize", "magnification", "largesize",
        "autohide", "autohide-delay", "autohide-time-modifier",
        "orientation", "mineffect", "show-recents",
        "minimize-to-application", "launchanim", "show-process-indicators",
        "showhidden", "scroll-to-open", "static-only",
    ]

    /// Les réglages d'apparence actuels du Dock.
    static func currentSettings() -> DockSettings {
        var settings = DockSettings()
        for key in settingsKeys {
            guard let raw = CFPreferencesCopyAppValue(key as CFString, domain) else { continue }
            if let number = raw as? NSNumber {
                // Les booléens arrivent aussi en NSNumber ; on distingue par le type CF.
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    settings.values[key] = .bool(number.boolValue)
                } else {
                    settings.values[key] = .number(number.doubleValue)
                }
            } else if let string = raw as? String {
                settings.values[key] = .string(string)
            }
        }
        return settings
    }

    /// Les éléments actuellement épinglés dans le Dock.
    static func currentItems() -> [DockItem] {
        guard let raw = CFPreferencesCopyAppValue(persistentAppsKey, domain) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap(item(from:))
    }

    /// Remplace les apps épinglées par `items`, applique `settings` s'il y en a, puis relance le Dock.
    static func apply(_ items: [DockItem], settings: DockSettings? = nil) throws {
        let plist = items.map(dictionary(for:)) as CFArray
        CFPreferencesSetAppValue(persistentAppsKey, plist, domain)
        if let settings {
            for key in settingsKeys {
                CFPreferencesSetAppValue(key as CFString, cfValue(settings.values[key]), domain)
            }
        }
        guard CFPreferencesAppSynchronize(domain) else {
            throw DockServiceError.synchronizeFailed
        }
        try restartDock()
    }

    private static let dockBundleID = "com.apple.dock"
    private static let dockAppURL = URL(fileURLWithPath: "/System/Library/CoreServices/Dock.app")

    /// Relance le Dock et attend qu'il soit revenu.
    ///
    /// `killall Dock` s'en remet à launchd pour relancer le Dock ; quand la session est en mode
    /// « à la demande » (fréquent après une longue session), le Dock ne revient pas et la
    /// bureau semble planté. `launchctl kickstart -k` l'arrête et le relance en une seule
    /// opération gérée par launchd, puis on vérifie sa présence et on l'ouvre au besoin.
    static func restartDock() throws {
        let status = run("/bin/launchctl", ["kickstart", "-k", "gui/\(getuid())/com.apple.Dock.agent"])
        if status != 0 {
            let killStatus = run("/usr/bin/killall", ["Dock"])
            guard killStatus == 0 else { throw DockServiceError.restartFailed(status) }
        }
        try waitForDock()
    }

    private static func waitForDock() throws {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if isDockRunning { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        // launchd ne l'a pas relancé : on l'ouvre explicitement.
        NSWorkspace.shared.openApplication(at: dockAppURL, configuration: .init()) { _, _ in }
        let secondDeadline = Date().addingTimeInterval(3)
        while Date() < secondDeadline {
            if isDockRunning { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw DockServiceError.dockDidNotComeBack
    }

    private static var isDockRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleID).isEmpty
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func cfValue(_ value: DockSettings.Value?) -> CFPropertyList? {
        switch value {
        case .bool(let b)?: return b as CFBoolean
        case .number(let n)?: return n as CFNumber
        case .string(let s)?: return s as CFString
        case nil: return nil // retire la clé : retour à la valeur par défaut
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
