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

    init(store: VaultViewModel) {
        self.store = store
        self.panel = QuickVaultPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let rootView = VaultPanelView(store: store) { [weak self] in
            self?.hide()
        }
        panel.contentView = NSHostingView(rootView: rootView)
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        positionPanel()
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
        if panel.attachedSheet == nil {
            hide()
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
