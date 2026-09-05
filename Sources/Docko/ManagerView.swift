import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension ProfileStore {
    /// Binding par identifiant : reste valide même si la liste est réordonnée ou modifiée.
    func binding(for id: UUID) -> Binding<DockProfile>? {
        guard let current = profile(id: id) else { return nil }
        return Binding(
            get: { self.profile(id: id) ?? current },
            set: { self.update($0) }
        )
    }
}

struct ManagerView: View {
    @EnvironmentObject private var store: ProfileStore
    @State private var selection: UUID?
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 320)
        } detail: {
            if let selection, let binding = store.binding(for: selection) {
                ProfileEditorView(profile: binding)
                    .id(selection)
            } else {
                placeholder
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .toolbar { toolbarContent }
        .confirmationDialog(
            "Supprimer ce profil ?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) { deleteSelected() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le Dock actuel n'est pas modifié.")
        }
        .alert("Docko", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            if selection == nil { selection = store.activeProfileID ?? store.profiles.first?.id }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(store.profiles) { profile in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: profile.colorHex))
                        .frame(width: 10, height: 10)
                    Text(profile.name)
                        .lineLimit(1)
                    Spacer()
                    if profile.id == store.activeProfileID {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .help("Profil actuellement appliqué")
                    }
                    Text("\(profile.items.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                .tag(profile.id)
            }
            .onMove { store.moveProfiles(from: $0, to: $1) }
        }
        .listStyle(.sidebar)
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(store.profiles.isEmpty ? "Aucun profil" : "Sélectionne un profil")
                .font(.title3)
                .foregroundStyle(.secondary)
            if store.profiles.isEmpty {
                Button("Enregistrer le Dock actuel comme profil") { captureCurrentDock() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("Depuis le Dock actuel…") { captureCurrentDock() }
                Button("Profil vide…") { createEmptyProfile() }
            } label: {
                Label("Nouveau profil", systemImage: "plus")
            }
            .help("Nouveau profil")

            Button {
                duplicateSelected()
            } label: {
                Label("Dupliquer", systemImage: "plus.square.on.square")
            }
            .disabled(selection == nil)
            .help("Dupliquer le profil sélectionné")

            Button {
                confirmDelete = true
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
            .disabled(selection == nil)
            .help("Supprimer le profil sélectionné")

            Menu {
                Button("Importer des profils…") { importProfiles() }
                Button("Exporter tous les profils…") { exportProfiles() }
                    .disabled(store.profiles.isEmpty)
            } label: {
                Label("Importer / Exporter", systemImage: "square.and.arrow.up.on.square")
            }
            .help("Importer ou exporter des profils (JSON)")
        }
    }

    // MARK: - Actions

    private func captureCurrentDock() {
        guard let name = Prompts.askForName(
            title: "Nouveau profil depuis le Dock actuel",
            message: "Les apps épinglées et les espaceurs du Dock actuel seront enregistrés dans ce profil.",
            defaultName: "Profil \(store.profiles.count + 1)"
        ) else { return }
        let profile = store.captureCurrentDock(named: name)
        selection = profile.id
    }

    private func createEmptyProfile() {
        guard let name = Prompts.askForName(
            title: "Nouveau profil vide",
            defaultName: "Profil \(store.profiles.count + 1)",
            confirmTitle: "Créer"
        ) else { return }
        let profile = store.createEmptyProfile(named: name)
        selection = profile.id
    }

    private func duplicateSelected() {
        guard let selection, let copy = store.duplicate(id: selection) else { return }
        self.selection = copy.id
    }

    private func deleteSelected() {
        guard let id = selection else { return }
        let index = store.profiles.firstIndex { $0.id == id } ?? 0
        store.delete(id: id)
        let remaining = store.profiles
        selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }

    private func importProfiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choisis un fichier exporté par Docko."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let count = try store.importData(data)
            if count == 0 { errorMessage = "Aucun profil trouvé dans ce fichier." }
            if selection == nil { selection = store.profiles.last?.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportProfiles() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Docko-profils.json"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try store.exportData()
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
