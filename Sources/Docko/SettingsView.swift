import AppKit
import SwiftUI

/// Réglages de l'application, affichés dans le volet de détail de la fenêtre de gestion.
struct SettingsView: View {
    @EnvironmentObject private var store: ProfileStore
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                generalSection
                profileShortcutsSection
                commandsSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(Theme.canvas)
        .alert("Docko", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Réglages")
                    .font(.title2.weight(.semibold))
                Text("Docko \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 4)
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section {
            Toggle("Lancement au démarrage", isOn: launchAtLoginBinding)
            if LoginItemService.requiresApproval {
                HStack {
                    Text("macOS attend ton autorisation dans Réglages Système.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Ouvrir…") { LoginItemService.openSystemSettings() }
                }
            }
            Toggle("Afficher le nom du profil dans la barre des menus", isOn: $store.showsNameInMenuBar)
            Toggle("Afficher Docko dans le Dock", isOn: $store.showsInDock)
                .help("Icône et point « en cours d'exécution » dans le Dock, présence dans ⌘⇥")
        } header: {
            Text("Général")
        }
    }

    private var profileShortcutsSection: some View {
        Section {
            if store.profiles.isEmpty {
                Text("Aucun profil.").foregroundStyle(.secondary)
            }
            ForEach(store.profiles) { profile in
                shortcutRow(
                    title: profile.name,
                    shortcut: hotkeyBinding(for: profile.id),
                    onClear: { setHotkey(nil, for: profile.id) }
                ) {
                    ColorSwatch(hex: profile.colorHex, size: 12)
                        .frame(width: 18)
                }
            }
        } header: {
            Text("Appliquer un profil")
        }
    }

    private var commandsSection: some View {
        Section {
            ForEach(AppCommand.allCases) { command in
                shortcutRow(
                    title: command.shortTitle,
                    shortcut: commandBinding(for: command),
                    onClear: { setCommandShortcut(nil, for: command) }
                ) {
                    Image(systemName: command.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                }
            }
        } header: {
            Text("Commandes")
        }
    }

    /// Ligne « icône, libellé, enregistreur, effacer ». Les raccourcis sont globaux et
    /// exigent un modificateur ; l'enregistreur refuse une touche seule.
    private func shortcutRow<Leading: View>(
        title: String,
        shortcut: Binding<Shortcut?>,
        onClear: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        HStack(spacing: 10) {
            leading()
            Text(title)
                .lineLimit(1)
            Spacer()
            ShortcutRecorder(shortcut: shortcut, placeholder: "Aucun", requiresModifiers: true)
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Retirer le raccourci")
            .disabled(shortcut.wrappedValue == nil)
        }
    }

    // MARK: - Bindings

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { store.launchAtLogin },
            set: { enabled in
                do {
                    try LoginItemService.setEnabled(enabled)
                    store.launchAtLogin = enabled
                    if enabled, LoginItemService.requiresApproval { LoginItemService.openSystemSettings() }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        )
    }

    private func hotkeyBinding(for id: UUID) -> Binding<Shortcut?> {
        Binding(
            get: { store.profile(id: id)?.hotkey },
            set: { setHotkey($0, for: id) }
        )
    }

    private func setHotkey(_ shortcut: Shortcut?, for id: UUID) {
        do {
            try store.setHotkey(shortcut, forProfile: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commandBinding(for command: AppCommand) -> Binding<Shortcut?> {
        Binding(
            get: { store.shortcut(for: command) },
            set: { setCommandShortcut($0, for: command) }
        )
    }

    private func setCommandShortcut(_ shortcut: Shortcut?, for command: AppCommand) {
        do {
            try store.setShortcut(shortcut, for: command)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Enregistreur de raccourci

/// Bouton qui capture la prochaine touche pressée. Échap annule.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    var placeholder: String
    var requiresModifiers: Bool

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Appuie sur une touche…" : (shortcut?.display ?? placeholder))
                .font(.system(.body, design: .rounded).monospacedDigit())
                .foregroundStyle(shortcut == nil && !recording ? Color.secondary : Color.primary)
                .frame(minWidth: 90)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : nil)
        .help(requiresModifiers ? "Clique puis appuie sur la combinaison, avec ⌘, ⌥, ⌃ ou ⇧. Échap annule." : "Clique puis appuie sur une touche. Échap annule.")
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Échap
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection(Shortcut.relevantFlags)
            if requiresModifiers && flags.isEmpty {
                NSSound.beep()
                return nil
            }
            shortcut = Shortcut(event: event)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}
