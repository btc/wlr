import AppKit
import Carbon.HIToolbox

/// A single system-wide hot key via Carbon's RegisterEventHotKey.
///
/// Chosen over NSEvent.addGlobalMonitorForEvents because the Carbon API needs no
/// Accessibility permission — it registers with the window server directly rather than
/// tapping the event stream.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    private static var instances: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1

    private var identifier: UInt32 = 0

    /// - Parameters:
    ///   - keyCode: a virtual key code, e.g. `kVK_ANSI_R`.
    ///   - modifiers: Carbon modifier mask, e.g. `controlKey | optionKey | cmdKey`.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        unregister()
        self.action = action

        identifier = HotKey.nextID
        HotKey.nextID += 1
        HotKey.instances[identifier] = self

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, _ in
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
            if let instance = HotKey.instances[hotKeyID.id] {
                DispatchQueue.main.async { instance.action?() }
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, nil, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x574c5220 /* "WLR " */), id: identifier)
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
        HotKey.instances[identifier] = nil
        action = nil
    }

    deinit { unregister() }
}
