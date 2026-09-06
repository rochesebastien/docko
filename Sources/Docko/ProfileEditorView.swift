import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProfileEditorView: View {
    @EnvironmentObject private var store: ProfileStore
    @Binding var profile: DockProfile
    var onDuplicate: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var errorMessage: String?
    @State private var confirmReplace = false
    @StateObject private var colorPanel = ColorPanelBridge()

    private var isActive: Bool { store.activeProfileID == profile.id }
    private var appCount: Int { profile.items.filter { !$0.isSpacer }.count }
    private var spacerCount: Int { profile.items.filter(\.isSpacer).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            preview
            dockSettingsSection
            items
            footer
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.canvas)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                TextField("Nom du profil", text: $profile.name)
                    .textFieldStyle(.plain)
                    .font(.title.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 12)

                if isActive {
                    Pill(text: "Appliqué", systemImage: "checkmark", style: .success)
                }
                if let key = store.effectiveHotkey(for: profile) {
                    Pill(text: "\(store.leaderShortcut.display) puis \(key.display)", style: .neutral)
                        .help("Raccourci global de ce profil")
                }

                Menu {
                    Button("Dupliquer") { onDuplicate() }
                    Button("Remplacer par le Dock actuel…") { confirmReplace = true }
                    Divider()
                    Button("Supprimer…", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Autres actions")
            }

            HStack(spacing: 8) {
                customColorChip
                ForEach(DockProfile.defaultColors, id: \.self) { hex in
                    colorChip(hex)
                }
                Spacer()
            }
        }
    }

    private var isCustomColor: Bool {
        !DockProfile.defaultColors.contains { $0.uppercased() == profile.colorHex.uppercased() }
    }

    /// Pastille « couleur libre » : même forme que les autres, roue chromatique en anneau.
    /// Un clic ouvre le panneau de couleurs de macOS, dont les changements sont appliqués en direct.
    private var customColorChip: some View {
        Button {
            colorPanel.open(initial: profile.colorHex) { profile.colorHex = $0 }
        } label: {
            Circle()
                .fill(Color(hex: profile.colorHex))
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                center: .center
                            ),
                            lineWidth: 3
                        )
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(isCustomColor ? 0.9 : 0), lineWidth: 2)
                        .padding(-3)
                )
        }
        .buttonStyle(.plain)
        .frame(width: 22, height: 22)
        .help("Couleur personnalisée")
    }

    private func colorChip(_ hex: String) -> some View {
        let selected = profile.colorHex.uppercased() == hex.uppercased()
        return Button {
            profile.colorHex = hex
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(selected ? 0.9 : 0), lineWidth: 2)
                        .padding(-3)
                )
                .overlay(Circle().strokeBorder(.black.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .frame(width: 22, height: 22)
        .help(hex)
    }

    // MARK: - Aperçu du Dock

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Aperçu")
            DockPreview(items: profile.items)
        }
    }

    // MARK: - Réglages du Dock

    private var dockSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Réglages du Dock")
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    if let settings = profile.dockSettings {
                        Text(settings.summary)
                            .lineLimit(2)
                        Text("Appliqués avec le profil : taille, agrandissement, masquage, position, effets…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Ce profil ne modifie pas les réglages du Dock")
                        Text("Mémorise-les pour que ce profil restaure aussi la taille, l'agrandissement, le masquage, la position…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if profile.dockSettings != nil {
                    Button("Mettre à jour") { store.captureDockSettings(id: profile.id) }
                        .help("Remplacer par les réglages actuels du Dock")
                    Button("Retirer") { store.removeDockSettings(id: profile.id) }
                        .help("Ce profil ne touchera plus aux réglages du Dock")
                } else {
                    Button("Mémoriser les réglages actuels") { store.captureDockSettings(id: profile.id) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .card()
        }
    }

    // MARK: - Éléments

    private var items: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(
                text: "Éléments",
                trailing: profile.items.isEmpty ? nil : "\(appCount) apps · \(spacerCount) espaces"
            )

            VStack(spacing: 0) {
                if profile.items.isEmpty {
                    EmptyState(
                        systemImage: "square.dashed",
                        title: "Ce profil est vide",
                        subtitle: "Ajoute des apps, ou remplace-le par le Dock actuel."
                    ) {
                        HStack {
                            Button("Ajouter une app…") { addApplications() }
                            Button("Remplacer par le Dock actuel…") { confirmReplace = true }
                        }
                    }
                } else {
                    List {
                        ForEach(profile.items) { item in
                            DockItemRow(item: item) {
                                profile.items.removeAll { $0.id == item.id }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 10))
                        }
                        .onMove { profile.items.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { profile.items.remove(atOffsets: $0) }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }

                Divider()

                HStack(spacing: 4) {
                    Button {
                        addApplications()
                    } label: {
                        Label("Ajouter une app", systemImage: "plus")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)

                    Menu {
                        Button("Espace") { profile.items.append(.spacer(small: false)) }
                        Button("Petit espace") { profile.items.append(.spacer(small: true)) }
                    } label: {
                        Label("Ajouter un espace", systemImage: "arrow.left.and.right")
                            .font(.callout)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Spacer()

                    Text("Glisse les lignes pour réordonner")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.surfaceRaised.opacity(0.6))
            }
            .card()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pied

    private var footer: some View {
        HStack {
            Text(profile.dockSettings == nil
                 ? "Applique le profil pour remplacer les apps épinglées du Dock. Les dossiers et les réglages du Dock ne bougent pas."
                 : "Applique le profil pour remplacer les apps épinglées et les réglages du Dock. Les dossiers ne bougent pas.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button {
                applyProfile()
            } label: {
                Label(isActive ? "Réappliquer au Dock" : "Appliquer au Dock", systemImage: "dock.rectangle")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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

// MARK: - Aperçu façon Dock

/// Bandeau qui imite le Dock : icônes sur verre dépoli, espaceurs en pointillés.
struct DockPreview: View {
    let items: [DockItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if items.isEmpty {
                    Text("Aucune app épinglée")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                } else {
                    ForEach(items) { item in
                        previewTile(item)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.border)
        )
    }

    @ViewBuilder
    private func previewTile(_ item: DockItem) -> some View {
        switch item.kind {
        case .app:
            AppIconView(item: item, size: 36)
                .help(item.displayName)
        case .spacer:
            spacerMark(width: 22)
        case .smallSpacer:
            spacerMark(width: 12)
        }
    }

    private func spacerMark(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundStyle(.tertiary)
            .frame(width: width, height: 36)
            .help("Espace")
    }
}

// MARK: - Ligne

struct DockItemRow: View {
    let item: DockItem
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(item: item, size: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .foregroundStyle(item.isSpacer ? .secondary : .primary)
                if let path = item.path {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            if !item.existsOnDisk {
                Pill(text: "Introuvable", systemImage: "exclamationmark.triangle.fill", style: .neutral)
                    .help("Application introuvable sur le disque")
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0)
            .help("Retirer du profil")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: - Panneau de couleurs

/// Relie le panneau de couleurs partagé de macOS à une fermeture SwiftUI.
final class ColorPanelBridge: NSObject, ObservableObject {
    private var onChange: ((String) -> Void)?
    private var ownsPanel = false

    func open(initial hex: String, onChange: @escaping (String) -> Void) {
        self.onChange = onChange
        ownsPanel = true
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = NSColor(hex: hex) ?? .systemBlue
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))
        panel.isContinuous = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorDidChange(_ sender: NSColorPanel) {
        onChange?(sender.color.hexString)
    }

    deinit {
        guard ownsPanel else { return }
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
    }
}
