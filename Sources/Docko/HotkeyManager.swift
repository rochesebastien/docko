import Carbon
import Foundation

/// Raccourcis globaux via Carbon (aucune permission d'accessibilité requise).
///
/// Fonctionnement en séquence : un déclencheur (⌘D par défaut) arme pendant un court
/// délai les touches des profils, enregistrées sans modificateur. La touche pressée
/// est renvoyée via `onChordKey`, puis tout est désarmé.
///
/// Les commandes de l'application (`AppCommand`) ont chacune un raccourci global
/// optionnel, avec modificateurs, actif en permanence.
final class HotkeyManager {
    var onLeader: (() -> Void)?
    var onChordKey: ((UInt32) -> Void)?
    var onCommand: ((AppCommand) -> Void)?

    private var handlerRef: EventHandlerRef?
    private var leaderRef: EventHotKeyRef?
    private var commandRefs: [EventHotKeyRef] = []
    private var chordRefs: [EventHotKeyRef] = []
    private var chordCodes: [UInt32] = []

    private let signature: OSType = 0x444F_434B // "DOCK"
    private static let leaderID: UInt32 = 1
    private static let commandBase: UInt32 = 100
    private static let chordBase: UInt32 = 1000

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
        unregisterLeader()
        unregisterCommands()
        disarmChord()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    // MARK: - Déclencheur

    func registerLeader(_ shortcut: Shortcut) {
        unregisterLeader()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: Self.leaderID)
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr {
            leaderRef = ref
        } else {
            NSLog("Docko: impossible d'enregistrer le raccourci \(shortcut.display) (\(status))")
        }
    }

    func unregisterLeader() {
        if let leaderRef { UnregisterEventHotKey(leaderRef) }
        leaderRef = nil
    }

    // MARK: - Commandes

    /// Remplace tous les raccourcis de commandes par ceux fournis.
    func registerCommands(_ shortcuts: [AppCommand: Shortcut]) {
        unregisterCommands()
        for (command, shortcut) in shortcuts {
            guard let index = AppCommand.allCases.firstIndex(of: command) else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: signature, id: Self.commandBase + UInt32(index))
            let status = RegisterEventHotKey(
                shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr, let ref {
                commandRefs.append(ref)
            } else {
                NSLog("Docko: impossible d'enregistrer le raccourci \(shortcut.display) pour « \(command.shortTitle) » (\(status))")
            }
        }
    }

    func unregisterCommands() {
        commandRefs.forEach { UnregisterEventHotKey($0) }
        commandRefs = []
    }

    // MARK: - Touches de profil

    func armChord(keyCodes: [UInt32]) {
        disarmChord()
        for code in keyCodes where !chordCodes.contains(code) {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: signature, id: Self.chordBase + UInt32(chordCodes.count))
            let status = RegisterEventHotKey(code, 0, id, GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else { continue }
            chordRefs.append(ref)
            chordCodes.append(code)
        }
    }

    func disarmChord() {
        chordRefs.forEach { UnregisterEventHotKey($0) }
        chordRefs = []
        chordCodes = []
    }

    var isChordArmed: Bool { !chordRefs.isEmpty }

    private func handle(id: UInt32) {
        if id == Self.leaderID {
            onLeader?()
        } else if id >= Self.commandBase, id < Self.chordBase {
            let index = Int(id - Self.commandBase)
            guard index < AppCommand.allCases.count else { return }
            onCommand?(AppCommand.allCases[index])
        } else if id >= Self.chordBase {
            let index = Int(id - Self.chordBase)
            guard index < chordCodes.count else { return }
            onChordKey?(chordCodes[index])
        }
    }
}
