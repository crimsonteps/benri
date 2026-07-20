import AppKit
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
    private var isMiniaturizing = false

    init(store: VaultViewModel, settings: AppSettings) {
        self.store = store
        self.panel = QuickVaultPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]
        panel.title = "QuickVault"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = true
        panel.hasShadow = true
        panel.contentMinSize = NSSize(width: 820, height: 520)

        let rootView = VaultPanelView(store: store, settings: settings) { [weak self] in
            self?.hide()
        }
        panel.contentView = NSHostingView(rootView: rootView)
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
        positionPanel()
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

    func windowDidResignKey(_ notification: Notification) {
        if CommandLine.arguments.contains("--show") {
            return
        }
        if isMiniaturizing || panel.isMiniaturized {
            return
        }
        if panel.attachedSheet == nil {
            hide()
        }
    }

    func windowWillMiniaturize(_ notification: Notification) {
        isMiniaturizing = true
    }

    func windowDidMiniaturize(_ notification: Notification) {
        isMiniaturizing = false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
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
