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

/// Ce que la barre latérale peut sélectionner : un profil, ou les réglages de l'app.
enum SidebarSelection: Hashable {
    case profile(UUID)
    case settings

    var profileID: UUID? {
        if case .profile(let id) = self { return id }
        return nil
    }
}

struct ManagerView: View {
    @EnvironmentObject private var store: ProfileStore
    @State private var selection: SidebarSelection?
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            switch selection {
            case .some(.settings):
                SettingsView()
            case .some(.profile(let id)):
                if let binding = store.binding(for: id) {
                    ProfileEditorView(
                        profile: binding,
                        onDuplicate: duplicateSelected,
                        onDelete: { confirmDelete = true }
                    )
                    .id(id)
                } else {
                    placeholder
                }
            case .none:
                placeholder
            }
        }
        .frame(minWidth: 700, minHeight: 440)
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
            if selection == nil, let id = store.activeProfileID ?? store.profiles.first?.id {
                selection = .profile(id)
            }
        }
    }

    // MARK: - Barre latérale

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader
            List(selection: $selection) {
                Section {
                    ForEach(store.profiles) { profile in
                        SidebarRow(profile: profile, isActive: profile.id == store.activeProfileID)
                            .tag(SidebarSelection.profile(profile.id))
                            .contextMenu { contextMenu(for: profile) }
                    }
                    .onMove { store.moveProfiles(from: $0, to: $1) }
                } header: {
                    Text("Profils")
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            settingsRow
            Divider()
            sidebarFooter
        }
        .background(.thinMaterial)
    }

    /// Identité de l'app au-dessus de la liste, sous les boutons de fenêtre.
    private var sidebarHeader: some View {
        HStack {
            Wordmark()
                .frame(height: 22)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    /// Accès aux réglages, posé sous la liste des profils, avec le même rendu qu'une ligne sélectionnée.
    private var settingsRow: some View {
        let selected = selection == .settings
        return Button {
            selection = .settings
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "gearshape")
                    .frame(width: 16)
                Text("Réglages")
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .help("Démarrage, barre des menus, raccourcis clavier")
    }

    private var sidebarFooter: some View {
        HStack(spacing: 4) {
            Menu {
                Button("Depuis le Dock actuel…") { captureCurrentDock() }
                Button("Profil vide…") { createEmptyProfile() }
            } label: {
                Label("Nouveau profil", systemImage: "plus")
                    .font(.callout)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Nouveau profil")

            Spacer()

            Menu {
                Button("Importer des profils…") { importProfiles() }
                Button("Exporter tous les profils…") { exportProfiles() }
                    .disabled(store.profiles.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.callout)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Importer ou exporter des profils (JSON)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func contextMenu(for profile: DockProfile) -> some View {
        Button("Appliquer au Dock") {
            do { try store.apply(id: profile.id) } catch { errorMessage = error.localizedDescription }
        }
        .disabled(profile.items.isEmpty)
        Divider()
        Button("Dupliquer") {
            if let copy = store.duplicate(id: profile.id) { selection = .profile(copy.id) }
        }
        Button("Supprimer…", role: .destructive) {
            selection = .profile(profile.id)
            confirmDelete = true
        }
    }

    private var placeholder: some View {
        EmptyState(
            systemImage: "dock.rectangle",
            title: store.profiles.isEmpty ? "Aucun profil" : "Sélectionne un profil",
            subtitle: store.profiles.isEmpty
                ? "Un profil mémorise les apps épinglées et les espaceurs du Dock. Commence par enregistrer ton Dock actuel."
                : "Choisis un profil dans la barre latérale pour le modifier ou l'appliquer."
        ) {
            if store.profiles.isEmpty {
                Button("Enregistrer le Dock actuel") { captureCurrentDock() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .background(Theme.canvas)
    }

    // MARK: - Actions

    private func captureCurrentDock() {
        guard let name = Prompts.askForName(
            title: "Nouveau profil depuis le Dock actuel",
            message: "Les apps épinglées et les espaceurs du Dock actuel seront enregistrés dans ce profil.",
            defaultName: "Profil \(store.profiles.count + 1)"
        ) else { return }
        let profile = store.captureCurrentDock(named: name)
        selection = .profile(profile.id)
    }

    private func createEmptyProfile() {
        guard let name = Prompts.askForName(
            title: "Nouveau profil vide",
            defaultName: "Profil \(store.profiles.count + 1)",
            confirmTitle: "Créer"
        ) else { return }
        let profile = store.createEmptyProfile(named: name)
        selection = .profile(profile.id)
    }

    private func duplicateSelected() {
        guard let id = selection?.profileID, let copy = store.duplicate(id: id) else { return }
        selection = .profile(copy.id)
    }

    private func deleteSelected() {
        guard let id = selection?.profileID else { return }
        let index = store.profiles.firstIndex { $0.id == id } ?? 0
        store.delete(id: id)
        let remaining = store.profiles
        selection = remaining.isEmpty ? nil : .profile(remaining[min(index, remaining.count - 1)].id)
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
            if selection == nil, let last = store.profiles.last { selection = .profile(last.id) }
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

// MARK: - Ligne de la barre latérale

private struct SidebarRow: View {
    let profile: DockProfile
    let isActive: Bool

    var body: some View {
        HStack(spacing: 9) {
            ColorSwatch(hex: profile.colorHex, size: 12)
            Text(profile.name)
                .lineLimit(1)
            Spacer(minLength: 6)
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Profil actuellement appliqué")
            }
        }
        .padding(.vertical, 2)
    }
}
