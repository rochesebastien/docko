import Foundation
import Combine

enum ProfileStoreError: LocalizedError {
    case profileNotFound
    case invalidImportFile
    /// Le raccourci est déjà pris par un profil ou une commande.
    case shortcutTaken(Shortcut, by: String)
    /// Un raccourci global doit comporter au moins un modificateur.
    case shortcutNeedsModifiers

    var errorDescription: String? {
        switch self {
        case .profileNotFound: return "Profil introuvable."
        case .invalidImportFile: return "Ce fichier n'est pas un export Docko valide."
        case .shortcutTaken(let shortcut, let owner):
            return "\(shortcut.display) est déjà utilisé par « \(owner) ». Choisis une autre combinaison."
        case .shortcutNeedsModifiers:
            return "Un raccourci global doit comporter au moins un modificateur (⌘, ⌥, ⌃ ou ⇧)."
        }
    }
}

/// Source de vérité de l'application : la liste des profils et les réglages,
/// persistés en JSON dans ~/Library/Application Support/Docko/.
final class ProfileStore: ObservableObject {
    @Published var profiles: [DockProfile] = [] { didSet { save() } }
    @Published var activeProfileID: UUID? = nil { didSet { save() } }
    @Published var showsNameInMenuBar: Bool = false { didSet { save() } }
    /// Icône dans le Dock (et point « en cours d'exécution »), en plus de la barre des menus.
    @Published var showsInDock: Bool = false { didSet { save() } }
    /// Préférence utilisateur. L'état réel côté macOS est géré par `LoginItemService`.
    @Published var launchAtLogin: Bool = false { didSet { save() } }
    /// Raccourcis globaux des commandes de l'application. Aucun par défaut.
    @Published var commandShortcuts: [AppCommand: Shortcut] = [:] { didSet { save() } }

    private struct Persisted: Codable {
        var version: Int = 1
        var profiles: [DockProfile]
        var activeProfileID: UUID?
        var showsNameInMenuBar: Bool
        var showsInDock: Bool
        var launchAtLogin: Bool
        /// Clés = `AppCommand.rawValue`, pour un JSON lisible et stable.
        var commandShortcuts: [String: Shortcut]

        init(profiles: [DockProfile], activeProfileID: UUID?, showsNameInMenuBar: Bool, showsInDock: Bool, launchAtLogin: Bool, commandShortcuts: [String: Shortcut]) {
            self.profiles = profiles
            self.activeProfileID = activeProfileID
            self.showsNameInMenuBar = showsNameInMenuBar
            self.showsInDock = showsInDock
            self.launchAtLogin = launchAtLogin
            self.commandShortcuts = commandShortcuts
        }

        // Tolère les fichiers écrits par une version antérieure (clés absentes).
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
            profiles = try c.decodeIfPresent([DockProfile].self, forKey: .profiles) ?? []
            activeProfileID = try c.decodeIfPresent(UUID.self, forKey: .activeProfileID)
            showsNameInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showsNameInMenuBar) ?? false
            showsInDock = try c.decodeIfPresent(Bool.self, forKey: .showsInDock) ?? false
            launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
            commandShortcuts = try c.decodeIfPresent([String: Shortcut].self, forKey: .commandShortcuts) ?? [:]
        }
    }

    /// Format des fichiers d'import/export.
    private struct ExportFile: Codable {
        var version: Int = 1
        var app: String = "Docko"
        var profiles: [DockProfile]
    }

    private let fileURL: URL
    private var isLoading = false

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("Docko", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("profiles.json")
        load()
    }

    // MARK: - Accès

    var activeProfile: DockProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first { $0.id == activeProfileID }
    }

    func profile(id: UUID) -> DockProfile? {
        profiles.first { $0.id == id }
    }

    // MARK: - Raccourcis

    func shortcut(for command: AppCommand) -> Shortcut? {
        commandShortcuts[command]
    }

    /// Associe (ou retire, avec nil) un raccourci global à une commande.
    func setShortcut(_ shortcut: Shortcut?, for command: AppCommand) throws {
        if let shortcut {
            try validate(shortcut, excludingCommand: command, excludingProfile: nil)
            commandShortcuts[command] = shortcut
        } else {
            commandShortcuts.removeValue(forKey: command)
        }
    }

    /// Associe (ou retire, avec nil) un raccourci global à un profil.
    func setHotkey(_ shortcut: Shortcut?, forProfile id: UUID) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        if let shortcut {
            try validate(shortcut, excludingCommand: nil, excludingProfile: id)
        }
        profiles[index].hotkey = shortcut
    }

    /// Profils qui ont un raccourci, prêts à être enregistrés.
    var profileShortcuts: [(id: UUID, shortcut: Shortcut, name: String)] {
        profiles.compactMap { profile in
            profile.hotkey.map { (id: profile.id, shortcut: $0, name: profile.name) }
        }
    }

    /// Refuse un raccourci sans modificateur, ou déjà pris par un autre profil ou une autre commande.
    private func validate(_ shortcut: Shortcut, excludingCommand: AppCommand?, excludingProfile: UUID?) throws {
        guard shortcut.hasModifiers else { throw ProfileStoreError.shortcutNeedsModifiers }
        for (command, existing) in commandShortcuts where command != excludingCommand && existing.collides(with: shortcut) {
            throw ProfileStoreError.shortcutTaken(shortcut, by: command.shortTitle)
        }
        for profile in profiles where profile.id != excludingProfile {
            if let existing = profile.hotkey, existing.collides(with: shortcut) {
                throw ProfileStoreError.shortcutTaken(shortcut, by: profile.name)
            }
        }
    }

    func profile(named name: String) -> DockProfile? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return profiles.first { $0.name.lowercased() == needle }
    }

    // MARK: - Mutations

    @discardableResult
    func captureCurrentDock(named name: String) -> DockProfile {
        let profile = DockProfile(
            name: uniqueName(name),
            colorHex: DockProfile.nextColor(after: profiles),
            items: DockService.currentItems(),
            dockSettings: DockService.currentSettings()
        )
        profiles.append(profile)
        activeProfileID = profile.id
        return profile
    }

    @discardableResult
    func createEmptyProfile(named name: String) -> DockProfile {
        let profile = DockProfile(name: uniqueName(name), colorHex: DockProfile.nextColor(after: profiles))
        profiles.append(profile)
        return profile
    }

    /// Remplace les éléments par ceux du Dock actuel, et rafraîchit les réglages si le profil les inclut.
    func replaceItemsWithCurrentDock(id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].items = DockService.currentItems()
        if profiles[index].dockSettings != nil {
            profiles[index].dockSettings = DockService.currentSettings()
        }
        activeProfileID = id
    }

    /// Mémorise les réglages actuels du Dock dans le profil.
    func captureDockSettings(id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].dockSettings = DockService.currentSettings()
    }

    /// Le profil cesse de toucher aux réglages du Dock.
    func removeDockSettings(id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].dockSettings = nil
    }

    /// Associe l'image au profil (copiée dans le dossier de Docko si nécessaire).
    func setWallpaper(id: UUID, imageURL: URL) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let path = try WallpaperService.store(imageURL)
        let previous = profiles[index].wallpaperPath
        profiles[index].wallpaperPath = path
        discardWallpaperIfUnused(previous)
    }

    /// Mémorise le fond d'écran actuel de l'écran principal dans le profil.
    /// Renvoie false si le fond actuel n'est pas un fichier image (fond dynamique, couleur…).
    @discardableResult
    func captureCurrentWallpaper(id: UUID) throws -> Bool {
        guard let current = WallpaperService.currentImagePath() else { return false }
        try setWallpaper(id: id, imageURL: URL(fileURLWithPath: current))
        return true
    }

    /// Le profil cesse de toucher au fond d'écran.
    func removeWallpaper(id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let previous = profiles[index].wallpaperPath
        profiles[index].wallpaperPath = nil
        discardWallpaperIfUnused(previous)
    }

    /// Supprime la copie locale d'une image si plus aucun profil ne s'en sert.
    private func discardWallpaperIfUnused(_ path: String?) {
        guard let path, !profiles.contains(where: { $0.wallpaperPath == path }) else { return }
        WallpaperService.discard(path)
    }

    func update(_ profile: DockProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
    }

    func delete(id: UUID) {
        let wallpaper = profile(id: id)?.wallpaperPath
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { activeProfileID = nil }
        discardWallpaperIfUnused(wallpaper)
    }

    @discardableResult
    func duplicate(id: UUID) -> DockProfile? {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = profiles[index]
        copy.id = UUID()
        copy.name = uniqueName(copy.name + " copie")
        copy.createdAt = Date()
        copy.items = copy.items.map { item in
            var item = item
            item.id = UUID()
            return item
        }
        profiles.insert(copy, at: index + 1)
        return copy
    }

    func moveProfiles(from source: IndexSet, to destination: Int) {
        profiles.move(fromOffsets: source, toOffset: destination)
    }

    /// Applique le profil : écrit les préférences du Dock, le relance, puis change
    /// le fond d'écran si le profil en a un. Le profil est marqué actif dès que le Dock
    /// est appliqué, même si le fond d'écran échoue ensuite.
    func apply(id: UUID) throws {
        guard let profile = profile(id: id) else { throw ProfileStoreError.profileNotFound }
        try DockService.apply(profile.items, settings: profile.dockSettings)
        activeProfileID = id
        if let wallpaperPath = profile.wallpaperPath {
            try WallpaperService.apply(path: wallpaperPath)
        }
    }

    /// Applique le profil suivant dans la liste (boucle sur le premier).
    func applyNext() throws {
        guard !profiles.isEmpty else { throw ProfileStoreError.profileNotFound }
        let currentIndex = profiles.firstIndex { $0.id == activeProfileID } ?? -1
        let next = profiles[(currentIndex + 1) % profiles.count]
        try apply(id: next.id)
    }

    // MARK: - Import / export

    func exportData(profileIDs: [UUID]? = nil) throws -> Data {
        let selected = profileIDs.map { ids in profiles.filter { ids.contains($0.id) } } ?? profiles
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(ExportFile(profiles: selected))
    }

    /// Importe les profils du fichier en leur attribuant de nouveaux identifiants.
    /// Renvoie le nombre de profils importés.
    @discardableResult
    func importData(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(ExportFile.self, from: data) else {
            throw ProfileStoreError.invalidImportFile
        }
        var imported: [DockProfile] = []
        for var profile in file.profiles {
            profile.id = UUID()
            profile.name = uniqueName(profile.name)
            profile.items = profile.items.map { item in
                var item = item
                item.id = UUID()
                return item
            }
            imported.append(profile)
            profiles.append(profile)
        }
        return imported.count
    }

    // MARK: - Persistance

    private func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let persisted = try? decoder.decode(Persisted.self, from: data) else { return }
        profiles = persisted.profiles
        activeProfileID = persisted.activeProfileID
        showsNameInMenuBar = persisted.showsNameInMenuBar
        showsInDock = persisted.showsInDock
        launchAtLogin = persisted.launchAtLogin
        // Les anciennes versions stockaient une touche seule, jouée après un déclencheur ⌘D.
        // Enregistrée telle quelle en global, elle confisquerait la touche à tout le système.
        profiles = profiles.map { profile in
            var profile = profile
            if let hotkey = profile.hotkey, !hotkey.hasModifiers { profile.hotkey = nil }
            return profile
        }
        commandShortcuts = persisted.commandShortcuts.reduce(into: [:]) { result, entry in
            if let command = AppCommand(rawValue: entry.key) { result[command] = entry.value }
        }
    }

    private func save() {
        guard !isLoading else { return }
        let persisted = Persisted(
            profiles: profiles,
            activeProfileID: activeProfileID,
            showsNameInMenuBar: showsNameInMenuBar,
            showsInDock: showsInDock,
            launchAtLogin: launchAtLogin,
            commandShortcuts: commandShortcuts.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(persisted)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Docko: échec de sauvegarde des profils: \(error)")
        }
    }

    private func uniqueName(_ base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? "Profil" : trimmed
        let existing = Set(profiles.map { $0.name.lowercased() })
        guard existing.contains(candidate.lowercased()) else { return candidate }
        var counter = 2
        while existing.contains("\(candidate) \(counter)".lowercased()) { counter += 1 }
        return "\(candidate) \(counter)"
    }
}
