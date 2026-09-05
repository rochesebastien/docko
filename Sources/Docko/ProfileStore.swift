import Foundation
import Combine

enum ProfileStoreError: LocalizedError {
    case profileNotFound
    case invalidImportFile

    var errorDescription: String? {
        switch self {
        case .profileNotFound: return "Profil introuvable."
        case .invalidImportFile: return "Ce fichier n'est pas un export Docko valide."
        }
    }
}

/// Source de vérité de l'application : la liste des profils et les réglages,
/// persistés en JSON dans ~/Library/Application Support/Docko/.
final class ProfileStore: ObservableObject {
    @Published var profiles: [DockProfile] = [] { didSet { save() } }
    @Published var activeProfileID: UUID? = nil { didSet { save() } }
    @Published var showsNameInMenuBar: Bool = false { didSet { save() } }
    /// Préférence utilisateur. L'état réel côté macOS est géré par `LoginItemService`.
    @Published var launchAtLogin: Bool = false { didSet { save() } }

    private struct Persisted: Codable {
        var version: Int = 1
        var profiles: [DockProfile]
        var activeProfileID: UUID?
        var showsNameInMenuBar: Bool
        var launchAtLogin: Bool

        init(profiles: [DockProfile], activeProfileID: UUID?, showsNameInMenuBar: Bool, launchAtLogin: Bool) {
            self.profiles = profiles
            self.activeProfileID = activeProfileID
            self.showsNameInMenuBar = showsNameInMenuBar
            self.launchAtLogin = launchAtLogin
        }

        // Tolère les fichiers écrits par une version antérieure (clés absentes).
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
            profiles = try c.decodeIfPresent([DockProfile].self, forKey: .profiles) ?? []
            activeProfileID = try c.decodeIfPresent(UUID.self, forKey: .activeProfileID)
            showsNameInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showsNameInMenuBar) ?? false
            launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
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
            items: DockService.currentItems()
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

    func replaceItemsWithCurrentDock(id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].items = DockService.currentItems()
        activeProfileID = id
    }

    func update(_ profile: DockProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
    }

    func delete(id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { activeProfileID = nil }
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

    /// Applique le profil au Dock (écrit les préférences et relance le Dock).
    func apply(id: UUID) throws {
        guard let profile = profile(id: id) else { throw ProfileStoreError.profileNotFound }
        try DockService.apply(profile.items)
        activeProfileID = id
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
        launchAtLogin = persisted.launchAtLogin
    }

    private func save() {
        guard !isLoading else { return }
        let persisted = Persisted(
            profiles: profiles,
            activeProfileID: activeProfileID,
            showsNameInMenuBar: showsNameInMenuBar,
            launchAtLogin: launchAtLogin
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
