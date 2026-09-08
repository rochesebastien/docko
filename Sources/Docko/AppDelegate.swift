import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = ProfileStore()

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var managerWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    private let hotkeys = HotkeyManager()

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

        hotkeys.onProfile = { [weak self] id in self?.applyReportingErrors(id: id) }
        hotkeys.onCommand = { [weak self] command in self?.run(command) }
        registerShortcutsIfChanged()

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

    private func storeDidChange() {
        refreshStatusTitle()
        applyActivationPolicy()
        registerShortcutsIfChanged()
    }

    // MARK: - Raccourcis globaux

    private var registeredCommands: [AppCommand: Shortcut] = [:]
    private var registeredProfiles: [UUID: Shortcut] = [:]

    /// Ré-enregistre auprès de Carbon uniquement ce qui a changé : le store publie à chaque mutation.
    private func registerShortcutsIfChanged() {
        if registeredCommands != store.commandShortcuts {
            registeredCommands = store.commandShortcuts
            hotkeys.registerCommands(store.commandShortcuts)
        }
        let profileShortcuts = store.profileShortcuts
        let byID = Dictionary(uniqueKeysWithValues: profileShortcuts.map { ($0.id, $0.shortcut) })
        if registeredProfiles != byID {
            registeredProfiles = byID
            hotkeys.registerProfiles(profileShortcuts)
        }
    }

    // MARK: - Commandes

    /// Point d'entrée unique des commandes, depuis le menu comme depuis un raccourci global.
    func run(_ command: AppCommand) {
        switch command {
        case .openManager: showManager()
        case .captureCurrentDock: captureCurrentDock()
        case .updateActiveProfile: updateActiveFromCurrentDock()
        case .openDockSettings: openDockSettings()
        case .restartDock: restartDock()
        case .openApp: showManager()
        case .quit: NSApp.terminate(nil)
        }
    }

    @objc private func performCommand(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let command = AppCommand(rawValue: raw) else { return }
        run(command)
    }

    /// Entrée de menu d'une commande, avec son raccourci global en indication grise s'il en a un.
    /// Pas de `keyEquivalent` : le raccourci Carbon est déjà global, un équivalent de menu
    /// déclencherait la commande deux fois quand le menu est ouvert.
    private func menuItem(for command: AppCommand, title: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title ?? command.title, action: #selector(performCommand(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = command.rawValue
        item.image = Self.symbol(command.symbol)
        if let shortcut = store.shortcut(for: command) {
            item.attributedTitle = Self.titleWithHint(item.title, hint: shortcut.display)
        }
        return item
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
                if let key = profile.hotkey {
                    item.attributedTitle = Self.titleWithHint(profile.name, hint: key.display)
                }
                item.image = NSColor.dotImage(hex: profile.colorHex)
                item.representedObject = profile.id
                item.state = profile.id == store.activeProfileID ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        menu.addItem(menuItem(for: .openManager))
        menu.addItem(menuItem(for: .captureCurrentDock))

        let update = menuItem(
            for: .updateActiveProfile,
            title: store.activeProfile.map { "Mettre à jour « \($0.name) » depuis le Dock actuel" }
        )
        update.isEnabled = store.activeProfile != nil
        menu.addItem(update)

        menu.addItem(.separator())

        let settingsMenu = NSMenu(title: "Réglages")

        settingsMenu.addItem(menuItem(for: .openDockSettings))

        let restart = menuItem(for: .restartDock)
        restart.toolTip = "Utile si le Dock reste affiché ou ne réagit plus à ses réglages."
        settingsMenu.addItem(restart)

        settingsMenu.addItem(.separator())

        let launch = NSMenuItem(title: "Lancement au démarrage", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = LoginItemService.isEnabled ? .on : .off
        if LoginItemService.requiresApproval {
            launch.state = .mixed
            launch.toolTip = "En attente d'autorisation dans Réglages Système › Général › Ouverture."
        }
        launch.image = Self.symbol("power")
        settingsMenu.addItem(launch)

        let showName = NSMenuItem(
            title: "Afficher le nom du profil dans la barre",
            action: #selector(toggleShowsName),
            keyEquivalent: ""
        )
        showName.target = self
        showName.state = store.showsNameInMenuBar ? .on : .off
        showName.image = Self.symbol("textformat")
        settingsMenu.addItem(showName)

        let showDock = NSMenuItem(title: "Afficher Docko dans le Dock", action: #selector(toggleShowsInDock), keyEquivalent: "")
        showDock.target = self
        showDock.state = store.showsInDock ? .on : .off
        showDock.image = Self.symbol("app.badge")
        settingsMenu.addItem(showDock)

        let settingsItem = NSMenuItem(title: "Réglages", action: nil, keyEquivalent: "")
        settingsItem.submenu = settingsMenu
        settingsItem.image = Self.symbol("slider.horizontal.3")
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        menu.addItem(menuItem(for: .openApp))
        menu.addItem(menuItem(for: .quit))
    }

    /// Symbole SF pour une entrée de menu, à la taille des menus système.
    private static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        return image?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    }

    private func refreshStatusTitle() {
        guard let button = statusItem?.button else { return }
        if store.showsNameInMenuBar, let active = store.activeProfile {
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

    private func captureCurrentDock() {
        guard let name = Prompts.askForName(
            title: "Nouveau profil depuis le Dock actuel",
            message: "Les apps épinglées et les espaceurs du Dock actuel seront enregistrés dans ce profil.",
            defaultName: "Profil \(store.profiles.count + 1)"
        ) else { return }
        store.captureCurrentDock(named: name)
    }

    private func updateActiveFromCurrentDock() {
        guard let active = store.activeProfile else { return }
        let ok = Prompts.confirm(
            title: "Mettre à jour « \(active.name) » ?",
            message: "Le contenu du profil sera remplacé par les apps actuellement épinglées dans le Dock.",
            confirmTitle: "Mettre à jour"
        )
        guard ok else { return }
        store.replaceItemsWithCurrentDock(id: active.id)
    }

    private func openDockSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Dépannage : le Dock garde parfois un état incohérent (masquage automatique ignoré,
    /// barre collée par-dessus les fenêtres) ; le relancer suffit.
    private func restartDock() {
        do {
            try DockService.restartDock()
        } catch {
            Prompts.showError(error, title: "Relancer le Dock")
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
}
