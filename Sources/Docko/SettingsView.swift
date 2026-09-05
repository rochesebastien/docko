import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ProfileStore
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Général") {
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
            }

            Section {
                HStack {
                    Text("Déclencheur")
                    Spacer()
                    ShortcutRecorder(shortcut: leaderBinding, placeholder: "⌘D", requiresModifiers: true)
                    Button("Réinitialiser") { store.leaderShortcut = .defaultLeader }
                        .disabled(store.leaderShortcut == .defaultLeader)
                }
                Text("Appuie sur le déclencheur, puis sur la touche du profil dans les deux secondes. Les raccourcis fonctionnent dans toutes les applications.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Raccourcis")
            }

            Section("Touche par profil") {
                if store.profiles.isEmpty {
                    Text("Aucun profil.").foregroundStyle(.secondary)
                }
                ForEach(Array(store.profiles.enumerated()), id: \.element.id) { index, profile in
                    HStack {
                        Circle().fill(Color(hex: profile.colorHex)).frame(width: 10, height: 10)
                        Text(profile.name)
                        Spacer()
                        Text(store.leaderShortcut.display + " puis")
                            .foregroundStyle(.secondary)
                        ShortcutRecorder(
                            shortcut: hotkeyBinding(for: profile.id),
                            placeholder: Shortcut.digit(index + 1)?.display ?? "—",
                            requiresModifiers: false
                        )
                        Button {
                            setHotkey(nil, for: profile.id)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .help("Revenir à la touche par défaut")
                        .disabled(profile.hotkey == nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .alert("Docko", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
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

    private var leaderBinding: Binding<Shortcut?> {
        Binding(
            get: { store.leaderShortcut },
            set: { if let shortcut = $0 { store.leaderShortcut = shortcut } }
        )
    }

    private func hotkeyBinding(for id: UUID) -> Binding<Shortcut?> {
        Binding(
            get: { store.profile(id: id)?.hotkey },
            set: { setHotkey($0, for: id) }
        )
    }

    private func setHotkey(_ shortcut: Shortcut?, for id: UUID) {
        guard var profile = store.profile(id: id) else { return }
        profile.hotkey = shortcut
        store.update(profile)
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
                .frame(minWidth: 90)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : nil)
        .help(requiresModifiers ? "Une touche avec ⌘, ⌥, ⌃ ou ⇧" : "Une touche seule, par exemple un chiffre")
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
