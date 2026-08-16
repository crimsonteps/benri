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

enum HotKeyAction: UInt32 {
    case commonText = 1
    case clipboard = 2
}

final class HotKeyManager {
    private var hotKeyRefs: [HotKeyAction: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private let actions: [HotKeyAction: () -> Void]

    init(actions: [HotKeyAction: () -> Void]) {
        self.actions = actions
    }

    deinit {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func register(_ hotKey: GlobalHotKey, for action: HotKeyAction) -> Bool {
        guard installEventHandlerIfNeeded() else { return false }

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x51564C54),
            id: action.rawValue
        )

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

        if let hotKeyRef = hotKeyRefs[action] {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs[action] = candidateRef
        return true
    }

    func unregister(_ action: HotKeyAction) {
        guard let hotKeyRef = hotKeyRefs.removeValue(forKey: action) else { return }
        UnregisterEventHotKey(hotKeyRef)
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
            benriHotKeyHandler,
            1,
            &eventSpec,
            userData,
            &eventHandlerRef
        )
        return handlerStatus == noErr
    }

    fileprivate func invoke(_ hotKeyID: UInt32) {
        guard let hotKeyAction = HotKeyAction(rawValue: hotKeyID),
              let action = actions[hotKeyAction]
        else { return }
        DispatchQueue.main.async {
            action()
        }
    }
}

private let benriHotKeyHandler: EventHandlerUPP = { _, event, userData in
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
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.invoke(hotKeyID.id)
    return noErr
}
