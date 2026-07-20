import Carbon.HIToolbox
import Foundation

enum GlobalHotKey: String, CaseIterable {
    case optionSpace
    case controlSpace
    case commandOptionSpace
    case controlOptionSpace

    var title: String {
        switch self {
        case .optionSpace: "⌥Space"
        case .controlSpace: "⌃Space"
        case .commandOptionSpace: "⌥⌘Space"
        case .controlOptionSpace: "⌃⌥Space"
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .optionSpace: UInt32(optionKey)
        case .controlSpace: UInt32(controlKey)
        case .commandOptionSpace: UInt32(cmdKey | optionKey)
        case .controlOptionSpace: UInt32(controlKey | optionKey)
        }
    }
}

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let action: () -> Void
    private var nextHotKeyID: UInt32 = 1

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

    func register(_ hotKey: GlobalHotKey) -> Bool {
        guard installEventHandlerIfNeeded() else { return false }

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x51564C54),
            id: nextHotKeyID
        )
        nextHotKeyID += 1

        var candidateRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &candidateRef
        )
        guard registerStatus == noErr, let candidateRef else { return false }

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = candidateRef
        return true
    }

    private func installEventHandlerIfNeeded() -> Bool {
        if eventHandlerRef != nil { return true }

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
        return handlerStatus == noErr
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
