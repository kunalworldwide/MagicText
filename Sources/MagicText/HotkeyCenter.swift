import Foundation
import AppKit
import Carbon.HIToolbox
import MagicTextCore

/// Carbon global hotkey registration. Not unit-testable — verified in-app.
final class HotkeyCenter {
    private var registered: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var current: Hotkey?
    var onTrigger: (() -> Void)?

    private static let signature: OSType = 0x4D545854 // "MTXT"

    func register(_ hotkey: Hotkey) -> Bool {
        unregister()
        installHandlerIfNeeded()

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, ref != nil else { return false }
        registered = ref
        current = hotkey
        return true
    }

    func unregister() {
        if let ref = registered {
            UnregisterEventHotKey(ref)
            registered = nil
        }
        current = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, kEventParamDirectObject,
                              typeEventHotKeyID,
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if hkID.signature == HotkeyCenter.signature {
                let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { center.onTrigger?() }
            }
            return noErr
        }
        var installed: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventSpec,
                            Unmanaged.passRetained(self).toOpaque()  as UnsafeMutableRawPointer?, &installed)
        handler = installed
    }
}
