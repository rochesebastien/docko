import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProfileEditorView: View {
    @EnvironmentObject private var store: ProfileStore
    @Binding var profile: DockProfile
    @State private var errorMessage: String?
    @State private var confirmReplace = false

    private var isActive: Bool { store.activeProfileID == profile.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            itemList
            footer
        }
        .padding()
        .alert("Docko", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Remplacer le contenu de « \(profile.name) » ?",
            isPresented: $confirmReplace,
            titleVisibility: .visible
        ) {
            Button("Remplacer", role: .destructive) {
                store.replaceItemsWithCurrentDock(id: profile.id)
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les éléments du profil seront remplacés par les apps actuellement épinglées dans le Dock.")
        }
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(spacing: 12) {
            ColorPicker("Couleur", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .help("Couleur du profil dans le menu")
            TextField("Nom du profil", text: $profile.name)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
            Spacer()
            if isActive {
                Label("Appliqué", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: profile.colorHex) },
            set: { profile.colorHex = NSColor($0).hexString }
        )
    }

    // MARK: - Liste des éléments

    private var itemList: some View {
        Group {
            if profile.items.isEmpty {
                VStack(spacing: 8) {
                    Text("Ce profil est vide.")
                        .foregroundStyle(.secondary)
                    Text("Ajoute des apps, ou remplace-le par le Dock actuel.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(profile.items) { item in
                        DockItemRow(item: item) {
                            profile.items.removeAll { $0.id == item.id }
                        }
                    }
                    .onMove { profile.items.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { profile.items.remove(atOffsets: $0) }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor))
        )
    }

    // MARK: - Pied

    private var footer: some View {
        HStack {
            Button {
                addApplications()
            } label: {
                Label("Ajouter une app…", systemImage: "plus.app")
            }

            Menu {
                Button("Espace") { profile.items.append(.spacer(small: false)) }
                Button("Petit espace") { profile.items.append(.spacer(small: true)) }
            } label: {
                Label("Ajouter un espace", systemImage: "arrow.left.and.right")
            }
            .fixedSize()

            Spacer()

            Text("\(profile.items.filter { !$0.isSpacer }.count) apps · \(profile.items.filter(\.isSpacer).count) espaces")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            Button("Remplacer par le Dock actuel") {
                confirmReplace = true
            }

            Button {
                applyProfile()
            } label: {
                Label("Appliquer au Dock", systemImage: "dock.rectangle")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(profile.items.isEmpty)
        }
    }

    // MARK: - Actions

    private func addApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choisis une ou plusieurs applications à épingler."
        panel.prompt = "Ajouter"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            profile.items.append(.app(path: url.path))
        }
    }

    private func applyProfile() {
        do {
            try store.apply(id: profile.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Ligne

struct DockItemRow: View {
    let item: DockItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .foregroundStyle(item.isSpacer ? .secondary : .primary)
                if let path = item.path {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            if !item.existsOnDisk {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("Application introuvable sur le disque")
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Retirer du profil")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .app:
            if let path = item.path {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app.dashed")
                    .foregroundStyle(.secondary)
            }
        case .spacer:
            Image(systemName: "arrow.left.and.right")
                .font(.title3)
                .foregroundStyle(.secondary)
        case .smallSpacer:
            Image(systemName: "arrow.left.and.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
