import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow

    init(
        settings: AppSettings,
        selectHotKey: @escaping (GlobalHotKey) -> Void
    ) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()

        window.delegate = self
        window.title = "valuet 设置"
        window.isReleasedWhenClosed = false
        window.level = .modalPanel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .clear
        window.isOpaque = false
        window.center()
        window.contentView = NSHostingView(
            rootView: SettingsView(
                settings: settings,
                selectHotKey: selectHotKey
            )
        )
    }

    func show() {
        window.appearance = NSApp.appearance
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeKey()

        DispatchQueue.main.async { [weak self] in
            guard let contentView = self?.window.contentView else { return }
            self?.hideScrollIndicators(in: contentView)
        }
    }

    private func hideScrollIndicators(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
        }

        for subview in view.subviews {
            hideScrollIndicators(in: subview)
        }
    }
}
