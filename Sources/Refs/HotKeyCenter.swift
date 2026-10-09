import Carbon.HIToolbox
import Foundation

/// Global hotkeys via Carbon's RegisterEventHotKey. It needs no Accessibility permission and
/// consumes the key press, unlike an NSEvent global monitor.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private static let signature: OSType = 0x5245_4653 // "REFS"
    private var registered: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var handlerInstalled = false

    /// Registers or replaces the hotkey for `id`. Returns false if macOS refused it, usually because
    /// another app already owns that combination.
    @discardableResult
    func register(id: UInt32, shortcut: Shortcut?, handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        unregister(id: id)
        handlers[id] = handler
        guard let shortcut else { return true }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        registered[id] = ref
        return true
    }

    func unregister(id: UInt32) {
        if let ref = registered.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
    }

    /// Temporarily releases every hotkey, e.g. while the user records a new shortcut.
    func suspendAll() {
        for ref in registered.values { UnregisterEventHotKey(ref) }
        registered.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == HotKeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKeyCenter.shared.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
