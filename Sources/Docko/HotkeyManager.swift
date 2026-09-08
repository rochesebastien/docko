import Carbon
import Foundation

/// Raccourcis globaux via Carbon (aucune permission d'accessibilité requise).
///
/// Deux familles de raccourcis, chacun une combinaison complète avec modificateurs,
/// active en permanence : un par profil (applique le profil) et un par commande
/// de l'application (`AppCommand`).
final class HotkeyManager {
    var onProfile: ((UUID) -> Void)?
    var onCommand: ((AppCommand) -> Void)?

    private var handlerRef: EventHandlerRef?
    private var commandRefs: [EventHotKeyRef] = []
    private var profileRefs: [EventHotKeyRef] = []
    /// Profils enregistrés, dans l'ordre des identifiants Carbon `profileBase + index`.
    private var profileIDs: [UUID] = []

    private let signature: OSType = 0x444F_434B // "DOCK"
    private static let commandBase: UInt32 = 100
    private static let profileBase: UInt32 = 1000

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue().handle(id: hotKeyID.id)
                return noErr
            },
            1,
            &spec,
            selfPointer,
            &handlerRef
        )
    }

    deinit {
        unregisterCommands()
        unregisterProfiles()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    // MARK: - Commandes

    /// Remplace tous les raccourcis de commandes par ceux fournis.
    func registerCommands(_ shortcuts: [AppCommand: Shortcut]) {
        unregisterCommands()
        for (command, shortcut) in shortcuts {
            guard let index = AppCommand.allCases.firstIndex(of: command) else { continue }
            if let ref = register(shortcut, id: Self.commandBase + UInt32(index), label: command.shortTitle) {
                commandRefs.append(ref)
            }
        }
    }

    func unregisterCommands() {
        commandRefs.forEach { UnregisterEventHotKey($0) }
        commandRefs = []
    }

    // MARK: - Profils

    /// Remplace tous les raccourcis de profils par ceux fournis (identifiant du profil → raccourci).
    func registerProfiles(_ shortcuts: [(id: UUID, shortcut: Shortcut, name: String)]) {
        unregisterProfiles()
        for entry in shortcuts {
            if let ref = register(entry.shortcut, id: Self.profileBase + UInt32(profileIDs.count), label: entry.name) {
                profileRefs.append(ref)
                profileIDs.append(entry.id)
            }
        }
    }

    func unregisterProfiles() {
        profileRefs.forEach { UnregisterEventHotKey($0) }
        profileRefs = []
        profileIDs = []
    }

    // MARK: - Carbon

    private func register(_ shortcut: Shortcut, id: UInt32, label: String) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else {
            NSLog("Docko: impossible d'enregistrer le raccourci \(shortcut.display) pour « \(label) » (\(status))")
            return nil
        }
        return ref
    }

    private func handle(id: UInt32) {
        if id >= Self.profileBase {
            let index = Int(id - Self.profileBase)
            guard index < profileIDs.count else { return }
            onProfile?(profileIDs[index])
        } else if id >= Self.commandBase {
            let index = Int(id - Self.commandBase)
            guard index < AppCommand.allCases.count else { return }
            onCommand?(AppCommand.allCases[index])
        }
    }
}
