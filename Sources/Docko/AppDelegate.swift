import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = ProfileStore()

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var managerWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Cycle de vie

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Docko")
            button.imagePosition = .imageLeading
        }
        menu.delegate = self
        statusItem.menu = menu
        refreshStatusTitle()

        LoginItemService.sync(with: store.launchAtLogin)

        // Le store publie avant la mutation ; on repasse par la main queue pour lire l'état à jour.
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshStatusTitle() }
            .store(in: &cancellables)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Schéma d'URL : docko://apply?name=Travail, docko://apply/Travail, docko://next, docko://manage
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handle(url) }
    }

    private func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "docko" else { return }
        switch url.host?.lowercased() {
        case "apply":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let queryName = components?.queryItems?.first { $0.name == "name" }?.value
            let pathName = url.pathComponents.dropFirst().joined(separator: "/")
            let name = queryName ?? (pathName.isEmpty ? nil : pathName)
            guard let name, let profile = store.profile(named: name) else {
                Prompts.showError(ProfileStoreError.profileNotFound, title: "docko://apply")
                return
            }
            applyReportingErrors(id: profile.id)
        case "next":
            do { try store.applyNext() } catch { Prompts.showError(error) }
        case "manage":
            showManager()
        default:
            break
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if store.profiles.isEmpty {
            let empty = NSMenuItem(title: "Aucun profil", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (index, profile) in store.profiles.enumerated() {
                let item = NSMenuItem(
                    title: profile.name,
                    action: #selector(applyProfile(_:)),
                    keyEquivalent: index < 9 ? "\(index + 1)" : ""
                )
                item.target = self
                item.image = NSColor.dotImage(hex: profile.colorHex)
                item.representedObject = profile.id
                item.state = profile.id == store.activeProfileID ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let capture = NSMenuItem(
            title: "Enregistrer le Dock actuel comme nouveau profil…",
            action: #selector(captureCurrentDock),
            keyEquivalent: "n"
        )
        capture.target = self
        menu.addItem(capture)

        let update = NSMenuItem(
            title: store.activeProfile.map { "Mettre à jour « \($0.name) » depuis le Dock actuel" }
                ?? "Mettre à jour le profil actif depuis le Dock actuel",
            action: #selector(updateActiveFromCurrentDock),
            keyEquivalent: "s"
        )
        update.target = self
        update.isEnabled = store.activeProfile != nil
        menu.addItem(update)

        menu.addItem(.separator())

        let manage = NSMenuItem(title: "Gérer les profils…", action: #selector(openManager), keyEquivalent: ",")
        manage.target = self
        menu.addItem(manage)

        let dockSettings = NSMenuItem(title: "Réglages du Dock…", action: #selector(openDockSettings), keyEquivalent: "")
        dockSettings.target = self
        menu.addItem(dockSettings)

        menu.addItem(.separator())

        let launch = NSMenuItem(title: "Lancement au démarrage", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = LoginItemService.isEnabled ? .on : .off
        if LoginItemService.requiresApproval {
            launch.state = .mixed
            launch.toolTip = "En attente d'autorisation dans Réglages Système › Général › Ouverture."
        }
        menu.addItem(launch)

        let showName = NSMenuItem(
            title: "Afficher le nom du profil dans la barre",
            action: #selector(toggleShowsName),
            keyEquivalent: ""
        )
        showName.target = self
        showName.state = store.showsNameInMenuBar ? .on : .off
        menu.addItem(showName)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quitter Docko", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func refreshStatusTitle() {
        guard let button = statusItem?.button else { return }
        if store.showsNameInMenuBar, let active = store.activeProfile {
            button.title = " " + active.name
        } else {
            button.title = ""
        }
    }

    // MARK: - Actions

    @objc private func applyProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        applyReportingErrors(id: id)
    }

    func applyReportingErrors(id: UUID) {
        do {
            try store.apply(id: id)
        } catch {
            Prompts.showError(error, title: "Impossible d'appliquer le profil")
        }
    }

    @objc private func captureCurrentDock() {
        guard let name = Prompts.askForName(
            title: "Nouveau profil depuis le Dock actuel",
            message: "Les apps épinglées et les espaceurs du Dock actuel seront enregistrés dans ce profil.",
            defaultName: "Profil \(store.profiles.count + 1)"
        ) else { return }
        store.captureCurrentDock(named: name)
    }

    @objc private func updateActiveFromCurrentDock() {
        guard let active = store.activeProfile else { return }
        let ok = Prompts.confirm(
            title: "Mettre à jour « \(active.name) » ?",
            message: "Le contenu du profil sera remplacé par les apps actuellement épinglées dans le Dock.",
            confirmTitle: "Mettre à jour"
        )
        guard ok else { return }
        store.replaceItemsWithCurrentDock(id: active.id)
    }

    @objc private func openManager() {
        showManager()
    }

    @objc private func openDockSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let enable = !(LoginItemService.isEnabled || LoginItemService.requiresApproval)
        do {
            try LoginItemService.setEnabled(enable)
            store.launchAtLogin = enable
            if enable, LoginItemService.requiresApproval {
                // macOS demande une validation manuelle : on amène l'utilisateur au bon endroit.
                LoginItemService.openSystemSettings()
            }
        } catch {
            Prompts.showError(error, title: "Lancement au démarrage")
        }
    }

    @objc private func toggleShowsName() {
        store.showsNameInMenuBar.toggle()
    }

    // MARK: - Fenêtre de gestion

    func showManager() {
        if managerWindow == nil {
            let root = ManagerView().environmentObject(store)
            let host = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: host)
            window.title = "Docko — Profils de Dock"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 820, height: 520))
            window.minSize = NSSize(width: 640, height: 400)
            window.isReleasedWhenClosed = false
            window.center()
            managerWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        managerWindow?.makeKeyAndOrderFront(nil)
    }
}
