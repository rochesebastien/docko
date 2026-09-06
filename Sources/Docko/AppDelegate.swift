import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = ProfileStore()

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var managerWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    private let hotkeys = HotkeyManager()
    private var chordTimer: Timer?
    private var chordArmed = false

    // MARK: - Cycle de vie

    func applicationWillFinishLaunching(_ notification: Notification) {
        terminateOtherInstances()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyActivationPolicy()

        MenuBarPlacement.seedPreferredPositionIfNeeded()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = MenuBarPlacement.autosaveName
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Docko")
            button.imagePosition = .imageLeading
        }
        menu.delegate = self
        statusItem.menu = menu
        refreshStatusTitle()
        // Diagnostic : une abscisse très négative signifie que l'icône est repliée par un outil
        // du type Hidden Bar (voir MenuBarPlacement).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, let frame = self.statusItem.button?.window?.frame else { return }
            NSLog("Docko: icône de barre des menus en x=%.0f (largeur %.0f)", frame.origin.x, frame.width)
        }

        LoginItemService.sync(with: store.launchAtLogin)

        hotkeys.onLeader = { [weak self] in self?.leaderPressed() }
        hotkeys.onChordKey = { [weak self] code in self?.chordKeyPressed(code) }
        registeredLeader = store.leaderShortcut
        hotkeys.registerLeader(store.leaderShortcut)

        // Le store publie avant la mutation ; on repasse par la main queue pour lire l'état à jour.
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.storeDidChange() }
            .store(in: &cancellables)

        // Sans fenêtre ni icône dans le Dock, un premier lancement serait invisible :
        // on ouvre la fenêtre de gestion tant qu'aucun profil n'existe.
        if store.profiles.isEmpty {
            showManager()
        }
    }

    /// Relancer l'app (double-clic dans le Finder, `open`) alors qu'elle tourne déjà :
    /// on montre la fenêtre de gestion plutôt que de ne rien faire.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showManager()
        return false
    }

    /// Une seule instance à la fois. Lancer une autre copie de Docko (une nouvelle build dans
    /// `dist/`, ou `/Applications` alors que `dist/` tourne encore) remplace l'ancienne au lieu
    /// d'empiler des icônes identiques dans la barre des menus.
    private func terminateOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        where other.processIdentifier != me {
            if !other.terminate() { other.forceTerminate() }
        }
    }

    /// Avec « Afficher dans le Dock », Docko devient une app ordinaire (icône et point dans le
    /// Dock, présence dans ⌘⇥) ; sinon elle ne vit que dans la barre des menus.
    private func applyActivationPolicy() {
        let wanted: NSApplication.ActivationPolicy = store.showsInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != wanted else { return }
        NSApp.setActivationPolicy(wanted)
    }

    private var registeredLeader: Shortcut?

    private func storeDidChange() {
        refreshStatusTitle()
        applyActivationPolicy()
        if registeredLeader != store.leaderShortcut {
            registeredLeader = store.leaderShortcut
            hotkeys.registerLeader(store.leaderShortcut)
        }
    }

    // MARK: - Raccourcis globaux (déclencheur puis touche)

    private func leaderPressed() {
        let codes = store.profiles.compactMap { store.effectiveHotkey(for: $0)?.keyCode }
        guard !codes.isEmpty else { return }
        hotkeys.armChord(keyCodes: codes)
        chordArmed = true
        refreshStatusTitle()
        chordTimer?.invalidate()
        chordTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.endChord()
        }
    }

    private func chordKeyPressed(_ keyCode: UInt32) {
        endChord()
        guard let profile = store.profiles.first(where: { store.effectiveHotkey(for: $0)?.keyCode == keyCode }) else { return }
        applyReportingErrors(id: profile.id)
    }

    private func endChord() {
        chordTimer?.invalidate()
        chordTimer = nil
        hotkeys.disarmChord()
        chordArmed = false
        refreshStatusTitle()
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
            for profile in store.profiles {
                let item = NSMenuItem(title: profile.name, action: #selector(applyProfile(_:)), keyEquivalent: "")
                item.target = self
                if let key = store.effectiveHotkey(for: profile) {
                    item.attributedTitle = Self.titleWithHint(profile.name, hint: "\(store.leaderShortcut.display) \(key.display)")
                }
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

        let settingsMenu = NSMenu(title: "Réglages")

        let manage = NSMenuItem(title: "Gérer les profils…", action: #selector(openManager), keyEquivalent: "")
        manage.target = self
        settingsMenu.addItem(manage)

        let settings = NSMenuItem(title: "Réglages de Docko…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        settingsMenu.addItem(settings)

        let dockSettings = NSMenuItem(title: "Réglages du Dock…", action: #selector(openDockSettings), keyEquivalent: "")
        dockSettings.target = self
        settingsMenu.addItem(dockSettings)

        settingsMenu.addItem(.separator())

        let launch = NSMenuItem(title: "Lancement au démarrage", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = LoginItemService.isEnabled ? .on : .off
        if LoginItemService.requiresApproval {
            launch.state = .mixed
            launch.toolTip = "En attente d'autorisation dans Réglages Système › Général › Ouverture."
        }
        settingsMenu.addItem(launch)

        let showName = NSMenuItem(
            title: "Afficher le nom du profil dans la barre",
            action: #selector(toggleShowsName),
            keyEquivalent: ""
        )
        showName.target = self
        showName.state = store.showsNameInMenuBar ? .on : .off
        settingsMenu.addItem(showName)

        let showDock = NSMenuItem(title: "Afficher Docko dans le Dock", action: #selector(toggleShowsInDock), keyEquivalent: "")
        showDock.target = self
        showDock.state = store.showsInDock ? .on : .off
        settingsMenu.addItem(showDock)

        let settingsItem = NSMenuItem(title: "Réglages", action: nil, keyEquivalent: "")
        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quitter Docko", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func refreshStatusTitle() {
        guard let button = statusItem?.button else { return }
        if chordArmed {
            button.title = " \(store.leaderShortcut.display) ▸ touche du profil…"
        } else if store.showsNameInMenuBar, let active = store.activeProfile {
            button.title = " " + active.name
        } else {
            button.title = ""
        }
    }

    /// Titre de menu avec l'indication du raccourci en gris, à la place d'un keyEquivalent.
    private static func titleWithHint(_ title: String, hint: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
        ])
        result.append(NSAttributedString(string: "    " + hint, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return result
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

    @objc private func openSettings() {
        showSettings()
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

    @objc private func toggleShowsInDock() {
        store.showsInDock.toggle()
    }

    // MARK: - Fenêtre de gestion

    func showManager() {
        if managerWindow == nil {
            let root = ManagerView().environmentObject(store)
            let host = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: host)
            window.title = "Docko"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 880, height: 560))
            window.minSize = NSSize(width: 700, height: 440)
            window.isReleasedWhenClosed = false
            window.center()
            managerWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        managerWindow?.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        if settingsWindow == nil {
            let root = SettingsView().environmentObject(store)
            let host = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: host)
            window.title = "Réglages de Docko"
            window.styleMask = [.titled, .closable]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
