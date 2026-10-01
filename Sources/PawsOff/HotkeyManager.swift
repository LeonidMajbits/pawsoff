import Carbon
import Foundation

final class HotkeyManager {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x50415753 // 'PAWS'
    private let identifier: UInt32 = 1
    private var down = false
    var onToggle: (() -> Void)?
    var isRegistered: Bool { hotKey != nil }

    func register() throws {
        precondition(Thread.isMainThread)
        guard hotKey == nil else { return }
        let types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let handlerStatus = types.withUnsafeBufferPointer { buffer in
            InstallEventHandler(GetEventDispatcherTarget(), { _, event, pointer in
                guard let event, let pointer else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(pointer).takeUnretainedValue()
                var keyID = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &keyID)
                guard status == noErr, keyID.signature == manager.signature,
                      keyID.id == manager.identifier else { return OSStatus(eventNotHandledErr) }
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                    manager.down = false
                } else if !manager.down {
                    manager.down = true
                    manager.onToggle?()
                }
                return noErr
            }, buffer.count, buffer.baseAddress,
            Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        }
        guard handlerStatus == noErr else {
            throw PawsOffError.message("Could not install shortcut handler (\(handlerStatus)).")
        }
        let keyID = EventHotKeyID(signature: signature, id: identifier)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_1), UInt32(controlKey), keyID,
                                        GetEventDispatcherTarget(), 0, &hotKey)
        guard status == noErr else {
            unregister()
            throw PawsOffError.message("Ctrl+1 is unavailable (\(status)). Check Mission Control’s Move to Desktop 1 shortcut.")
        }
    }
    /// The event tap consumes the activation chord's release; reset the Carbon latch
    /// after draining so the next physical press can activate the curtain again.
    func resetLatch() { down = false }
    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil; eventHandler = nil; down = false
    }
    deinit { unregister() }
}
