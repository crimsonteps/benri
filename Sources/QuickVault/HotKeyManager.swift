import Carbon.HIToolbox
import Foundation

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func registerOptionSpace() -> Bool {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            quickVaultHotKeyHandler,
            1,
            &eventSpec,
            userData,
            &eventHandlerRef
        )
        guard handlerStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x51564C54),
            id: 1
        )
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return registerStatus == noErr
    }

    fileprivate func invoke() {
        DispatchQueue.main.async { [action] in
            action()
        }
    }
}

private let quickVaultHotKeyHandler: EventHandlerUPP = { _, _, userData in
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.invoke()
    return noErr
}
