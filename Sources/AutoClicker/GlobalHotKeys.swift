import Carbon
import AutoClickCore

final class GlobalHotKeys {
    static let signature: OSType = 0x41434C4B
    private var handler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    var onMode: ((ClickMode) -> Void)?

    func register() -> String? {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalHotKeys>.fromOpaque(context).takeUnretainedValue()
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                          EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == GlobalHotKeys.signature else { return OSStatus(eventNotHandledErr) }
            owner.onMode?(id.id == 1 ? .hold : id.id == 2 ? .continuous : .off)
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { return "Keyboard shortcuts could not be installed (\(result))." }
        let bindings: [(UInt32, UInt32, UInt32)] = [
            (1, UInt32(kVK_PageUp), UInt32(cmdKey)),
            (2, UInt32(kVK_PageUp), UInt32(cmdKey | shiftKey)),
            (3, UInt32(kVK_PageDown), UInt32(cmdKey)),
            (4, UInt32(kVK_PageDown), UInt32(cmdKey | shiftKey))
        ]
        for (id, key, modifiers) in bindings {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(key, modifiers,
                EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else {
                unregister()
                return "A shortcut is already in use by another app (\(status)). Close that app and reopen Auto Clicker."
            }
            hotKeys.append(reference)
        }
        return nil
    }

    func unregister() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
