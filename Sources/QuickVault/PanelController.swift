import AppKit
import Carbon.HIToolbox
import SwiftUI

extension Notification.Name {
    static let quickVaultFocusSearch = Notification.Name("QuickVault.FocusSearch")
}

final class QuickVaultPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel: QuickVaultPanel
    private let store: VaultViewModel
    private let settings: AppSettings
    private var keyMonitor: Any?
    private var shouldPositionOnNextShow = true

    init(
        store: VaultViewModel,
        settings: AppSettings,
        openSettings: @escaping () -> Void
    ) {
        self.store = store
        self.settings = settings
        self.panel = QuickVaultPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]
        panel.title = "valuet"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentMinSize = NSSize(width: 820, height: 520)

        let rootView = VaultPanelView(
            store: store,
            settings: settings,
            openSettings: openSettings,
            onClose: { [weak self] in self?.hide() }
        )
        panel.contentView = NSHostingView(rootView: rootView)
        shouldPositionOnNextShow = !panel.setFrameUsingName("valuet.mainWindow")
        panel.setFrameAutosaveName("valuet.mainWindow")

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.panel.isKeyWindow,
                  self.panel.attachedSheet == nil
            else { return event }

            let modifiers = event.modifierFlags
            guard modifiers.intersection([.option, .control, .shift]).isEmpty else {
                return event
            }
            let usesCommand = modifiers.contains(.command)

            switch Int(event.keyCode) {
            case kVK_UpArrow:
                guard !usesCommand else { return event }
                switch self.store.keyboardPane {
                case .categories:
                    self.store.moveCategorySelection(-1)
                case .records:
                    self.moveRecordSelection(-1)
                case .value:
                    return event
                }
                return nil
            case kVK_DownArrow:
                guard !usesCommand else { return event }
                switch self.store.keyboardPane {
                case .categories:
                    self.store.moveCategorySelection(1)
                case .records:
                    self.moveRecordSelection(1)
                case .value:
                    return event
                }
                return nil
            case kVK_LeftArrow:
                if usesCommand || self.store.searchText.isEmpty {
                    self.store.moveKeyboardPaneLeft()
                    return nil
                }
                return event
            case kVK_RightArrow:
                if usesCommand || self.store.searchText.isEmpty {
                    self.store.moveKeyboardPaneRight()
                    return nil
                }
                return event
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if !usesCommand, self.store.keyboardPane == .value {
                    self.store.copySelectedRecord()
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func toggle() {
        if panel.isVisible && !panel.isMiniaturized {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if shouldPositionOnNextShow {
            positionPanel()
            shouldPositionOnNextShow = false
        }
        store.keyboardPane = .records
        if panel.isMiniaturized {
            panel.deminiaturize(nil)
        }
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.makeKey()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panel.makeKey()
            NotificationCenter.default.post(name: .quickVaultFocusSearch, object: nil)
        }
    }

    func showNewRecord() {
        show()
        store.beginNewRecord()
    }

    func hide() {
        guard panel.attachedSheet == nil else { return }
        panel.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    private func moveRecordSelection(_ direction: Int) {
        store.moveSelection(direction)
        if settings.autoCopyOnSelection {
            store.copySelectedRecord()
        }
    }

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.maxY - panelSize.height - 72
        )
        panel.setFrameOrigin(origin)
    }
}
