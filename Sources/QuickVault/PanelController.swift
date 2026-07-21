import AppKit
import ApplicationServices
import Carbon.HIToolbox
import OSLog
import SwiftUI

private let pasteLogger = Logger(
    subsystem: "com.crimsonteps.quickvault",
    category: "Paste"
)

extension Notification.Name {
    static let quickVaultFocusSearch = Notification.Name("QuickVault.FocusSearch")
}

final class QuickVaultPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel: QuickVaultPanel
    private let store: VaultViewModel
    private var keyMonitor: Any?
    private var shouldPositionOnNextShow = true
    private var shouldHideAfterEditorDismissal = false
    private var isHidingPanel = false
    private var previousApplication: NSRunningApplication?
    private var previousFocusedElement: AXUIElement?
    private var activationObserver: NSObjectProtocol?
    private var activationFallbackWorkItem: DispatchWorkItem?
    private var pendingPasteApplication: NSRunningApplication?
    private var pendingPasteFocusedElement: AXUIElement?

    init(
        store: VaultViewModel,
        settings: AppSettings,
        openSettings: @escaping () -> Void
    ) {
        self.store = store
        self.panel = QuickVaultPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView,
                .nonactivatingPanel
            ],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]
        panel.title = "benri"
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
            onClose: { [weak self] in
                self?.hide(restoringPreviousApplication: true)
            },
            onEditorDismissed: { [weak self] in self?.editorDidDismiss() }
        )
        panel.contentView = NSHostingView(rootView: rootView)
        shouldPositionOnNextShow = !panel.setFrameUsingName("benri.mainWindow")
        panel.setFrameAutosaveName("benri.mainWindow")

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.panel.isKeyWindow,
                  self.panel.attachedSheet == nil,
                  self.store.alert == nil
            else { return event }

            if self.store.isEditingRecordName {
                return event
            }

            if let textView = self.panel.firstResponder as? NSTextView,
               !textView.isFieldEditor {
                return event
            }

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
                    self.store.moveSelection(-1)
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
                    self.store.moveSelection(1)
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
                if usesCommand {
                    return event
                }
                if self.store.keyboardPane != .categories,
                   self.store.copySelectedRecord() {
                    pasteLogger.info("Enter requested paste")
                    self.hide(
                        restoringPreviousApplication: true,
                        pastingIntoPreviousApplication: true
                    )
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
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationFallbackWorkItem?.cancel()
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func toggle() {
        if panel.isVisible && !panel.isMiniaturized {
            if store.recordEditor != nil || store.categoryEditor != nil {
                shouldHideAfterEditorDismissal = true
                store.dismissEditors()
            } else {
                hide(restoringPreviousApplication: true)
            }
        } else {
            show()
        }
    }

    func show() {
        if !panel.isVisible {
            previousApplication = nil
            previousFocusedElement = nil

            if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
               frontmostApplication.processIdentifier
                   != NSRunningApplication.current.processIdentifier {
                previousApplication = frontmostApplication
                previousFocusedElement = focusedUIElement(for: frontmostApplication)
                pasteLogger.info(
                    "Showing nonactivating panel targetPID=\(frontmostApplication.processIdentifier, privacy: .public)"
                )
            }
        }

        if shouldPositionOnNextShow {
            positionPanel()
            shouldPositionOnNextShow = false
        }
        store.keyboardPane = .records
        if panel.isMiniaturized {
            panel.deminiaturize(nil)
        }
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panel.makeKey()
            NotificationCenter.default.post(name: .quickVaultFocusSearch, object: nil)
        }
    }

    func showNewRecord() {
        show()
        NSRunningApplication.current.activate(
            options: [.activateAllWindows, .activateIgnoringOtherApps]
        )
        NSApp.activate(ignoringOtherApps: true)
        store.beginNewRecord()
    }

    func hide(
        restoringPreviousApplication shouldRestore: Bool,
        pastingIntoPreviousApplication shouldPaste: Bool = false
    ) {
        guard panel.attachedSheet == nil, !isHidingPanel else { return }
        isHidingPanel = true
        defer { isHidingPanel = false }
        store.flushPendingRecordSave()
        panel.orderOut(nil)

        guard shouldRestore, let previousApplication else {
            if !shouldRestore {
                previousApplication = nil
            }
            previousFocusedElement = nil
            return
        }

        let focusedElement = previousFocusedElement
        self.previousApplication = nil
        previousFocusedElement = nil
        let canPaste = !shouldPaste || accessibilityPermissionGranted(prompt: true)
        pasteLogger.info(
            "Hiding panel paste=\(shouldPaste, privacy: .public) targetPID=\(previousApplication.processIdentifier, privacy: .public) targetActive=\(previousApplication.isActive, privacy: .public) accessibility=\(canPaste, privacy: .public)"
        )

        DispatchQueue.main.async { [weak self] in
            guard !previousApplication.isTerminated else { return }
            guard shouldPaste, canPaste else {
                previousApplication.activate(
                    options: [.activateAllWindows, .activateIgnoringOtherApps]
                )
                return
            }
            if previousApplication.isActive {
                pasteLogger.info("Target stayed active; pasting without app switch")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    self?.restoreFocusAndPaste(
                        focusedElement,
                        into: previousApplication
                    )
                }
                return
            }
            self?.activateAndPaste(
                into: previousApplication,
                focusedElement: focusedElement
            )
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide(restoringPreviousApplication: true)
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        guard
            panel.isVisible,
            panel.attachedSheet == nil,
            !isHidingPanel,
            !NSRunningApplication.current.isActive
        else { return }

        pasteLogger.debug("Nonactivating panel resigned key; hiding")
        hide(restoringPreviousApplication: false)
    }

    private func editorDidDismiss() {
        guard shouldHideAfterEditorDismissal else { return }
        shouldHideAfterEditorDismissal = false
        hide(restoringPreviousApplication: true)
    }

    private func focusedUIElement(for application: NSRunningApplication) -> AXUIElement? {
        guard AXIsProcessTrusted() else {
            pasteLogger.error("Accessibility not trusted while capturing focus")
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success else {
            pasteLogger.error(
                "Unable to capture focused element targetPID=\(application.processIdentifier, privacy: .public)"
            )
            return nil
        }
        pasteLogger.debug(
            "Captured focused element targetPID=\(application.processIdentifier, privacy: .public)"
        )
        return (focusedElement as! AXUIElement)
    }

    private func accessibilityPermissionGranted(prompt: Bool) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        pasteLogger.info("Accessibility trusted=\(granted, privacy: .public)")
        return granted
    }

    private func activateAndPaste(
        into application: NSRunningApplication,
        focusedElement: AXUIElement?
    ) {
        cancelPendingPaste()
        pendingPasteApplication = application
        pendingPasteFocusedElement = focusedElement

        let notificationCenter = NSWorkspace.shared.notificationCenter
        activationObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let activatedApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                activatedApplication.processIdentifier == application.processIdentifier
            else { return }

            Task { @MainActor [weak self] in
                pasteLogger.info("Received target activation notification")
                self?.completePendingPaste()
            }
        }

        let fallbackWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if !application.isActive {
                application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
            self.completePendingPaste()
        }
        activationFallbackWorkItem = fallbackWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: fallbackWorkItem)

        application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        if application.isActive {
            completePendingPaste()
        }
    }

    private func completePendingPaste() {
        guard let application = pendingPasteApplication else { return }
        let focusedElement = pendingPasteFocusedElement
        cancelPendingPaste()

        let delay = application.isActive ? 0.08 : 0.2
        if !application.isActive {
            application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.restoreFocusAndPaste(focusedElement, into: application)
        }
    }

    private func cancelPendingPaste() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        activationFallbackWorkItem?.cancel()
        activationFallbackWorkItem = nil
        pendingPasteApplication = nil
        pendingPasteFocusedElement = nil
    }

    private func restoreFocusAndPaste(
        _ focusedElement: AXUIElement?,
        into application: NSRunningApplication
    ) {
        if let focusedElement {
            let applicationElement = AXUIElementCreateApplication(
                application.processIdentifier
            )
            let applicationFocusResult = AXUIElementSetAttributeValue(
                applicationElement,
                kAXFocusedUIElementAttribute as CFString,
                focusedElement
            )
            let elementFocusResult = AXUIElementSetAttributeValue(
                focusedElement,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
            pasteLogger.info(
                "Focus restore appResult=\(applicationFocusResult.rawValue, privacy: .public) elementResult=\(elementFocusResult.rawValue, privacy: .public)"
            )
        } else {
            pasteLogger.info("No captured AX element; using target app current focus")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.postPasteShortcut()
        }
    }

    private func postPasteShortcut() {
        guard
            let source = CGEventSource(stateID: .privateState),
            let valueDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
            ),
            let valueUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
            )
        else {
            runAppleScriptPaste()
            return
        }

        source.localEventsSuppressionInterval = 0
        valueDown.flags = .maskCommand
        valueUp.flags = .maskCommand
        valueDown.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            valueUp.post(tap: .cghidEventTap)
            pasteLogger.info("Posted Command-V events")
        }
    }

    private func runAppleScriptPaste() {
        let script = NSAppleScript(
            source: "tell application \"System Events\" to keystroke \"v\" using command down"
        )
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if error != nil {
            pasteLogger.error("AppleScript paste fallback failed")
        } else {
            pasteLogger.info("AppleScript paste fallback executed")
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
