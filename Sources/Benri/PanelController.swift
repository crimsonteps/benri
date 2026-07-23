import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import OSLog
import SwiftUI

private let pasteLogger = Logger(
    subsystem: "com.crimsonteps.benri",
    category: "Paste"
)

extension Notification.Name {
    static let benriFocusSearch = Notification.Name("Benri.FocusSearch")
    static let benriClearSearchFocus = Notification.Name("Benri.ClearSearchFocus")
    static let benriSaveRecordEditor = Notification.Name("Benri.SaveRecordEditor")
    static let benriCancelRecordEditor = Notification.Name("Benri.CancelRecordEditor")
}

final class BenriPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel: BenriPanel
    private let store: VaultViewModel
    private var keyMonitor: Any?
    private var shouldHideAfterEditorDismissal = false
    private var isHidingPanel = false
    private var previousApplication: NSRunningApplication?
    private var previousFocusedElement: AXUIElement?
    private var pasteTask: Task<Void, Never>?
    private var pasteTransactionID: UInt64 = 0
    private var cancellables = Set<AnyCancellable>()

    init(
        store: VaultViewModel,
        settings: AppSettings,
        openSettings: @escaping () -> Void
    ) {
        self.store = store
        self.panel = BenriPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: VaultLayout.collapsedWindowWidth,
                height: VaultLayout.windowHeight
            ),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
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
        panel.title = "Benri"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.contentMinSize = NSSize(
            width: VaultLayout.collapsedWindowWidth,
            height: VaultLayout.windowHeight
        )
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let rootView = VaultPanelView(
            store: store,
            settings: settings,
            openSettings: openSettings,
            onClose: { [weak self] in
                self?.hide(restoringPreviousApplication: true)
            },
            onPasteRecord: { [weak self] recordID in
                self?.copyRecordAndPaste(recordID)
            },
            onEditorDismissed: { [weak self] in self?.editorDidDismiss() }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        Publishers.CombineLatest(
            store.$recordPanelMode.removeDuplicates(),
            store.$fatalErrorMessage
                .map { $0 != nil }
                .removeDuplicates()
        )
            .sink { [weak self] mode, hasFatalError in
                self?.updatePanelWidth(for: mode, hasFatalError: hasFatalError)
            }
            .store(in: &cancellables)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.panel.isKeyWindow || self.panel.attachedSheet?.isKeyWindow == true,
                  self.store.alert == nil
            else { return event }

            if self.handleRecordEditorShortcut(event) {
                return nil
            }
            guard self.panel.attachedSheet == nil else { return event }

            if self.store.isEditingRecordName, self.store.keyboardPane == .value {
                return event
            }

            if let textView = self.panel.firstResponder as? NSTextView,
               !textView.isFieldEditor,
               self.store.keyboardPane == .value {
                return event
            }

            let modifiers = event.modifierFlags
            guard modifiers.intersection([.option, .control, .shift]).isEmpty else {
                return event
            }
            let usesCommand = modifiers.contains(.command)

            switch Int(event.keyCode) {
            case kVK_ANSI_F:
                guard usesCommand else { return event }
                self.store.closeRecordPanel()
                self.store.keyboardPane = .records
                NotificationCenter.default.post(name: .benriFocusSearch, object: nil)
                return nil
            case kVK_UpArrow:
                guard !usesCommand else { return event }
                switch self.store.keyboardPane {
                case .categories:
                    self.store.moveCategorySelection(-1)
                case .records:
                    self.panel.makeFirstResponder(nil)
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
                    self.panel.makeFirstResponder(nil)
                    self.store.moveSelection(1)
                case .value:
                    return event
                }
                return nil
            case kVK_LeftArrow:
                if self.store.recordPanelMode == .preview {
                    self.store.closeRecordPanel()
                    return nil
                }
                if self.store.recordPanelMode == .edit {
                    return event
                }
                if usesCommand || self.store.searchText.isEmpty {
                    self.store.moveKeyboardPaneLeft()
                    return nil
                }
                return event
            case kVK_RightArrow:
                if self.store.recordPanelMode == .edit {
                    return event
                }
                if self.store.keyboardPane == .records {
                    self.panel.makeFirstResponder(nil)
                    self.store.showSelectedRecordPreview()
                    return nil
                }
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
                   self.copyRecordAndPaste() {
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    @discardableResult
    private func copyRecordAndPaste(_ recordID: UUID? = nil) -> Bool {
        guard store.recordPanelMode != .edit else { return false }
        if let recordID {
            store.selectRecord(recordID)
        }
        guard store.copySelectedRecord() else { return false }

        pasteLogger.info("Record requested paste")
        hide(
            restoringPreviousApplication: true,
            pastingIntoPreviousApplication: true
        )
        return true
    }

    private func handleRecordEditorShortcut(_ event: NSEvent) -> Bool {
        guard panel.attachedSheet?.isKeyWindow == true else { return false }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == kVK_Escape, modifiers.isEmpty {
            guard store.recordEditor != nil else { return false }
            NotificationCenter.default.post(name: .benriCancelRecordEditor, object: nil)
            return true
        }

        guard store.recordEditor != nil, modifiers == [.command] else { return false }
        switch Int(event.keyCode) {
        case kVK_ANSI_S, kVK_Return, kVK_ANSI_KeypadEnter:
            NotificationCenter.default.post(name: .benriSaveRecordEditor, object: nil)
            return true
        default:
            return false
        }
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        pasteTask?.cancel()
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
        cancelPendingPaste()

        if !panel.isVisible {
            store.closeRecordPanel()
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

        positionPanel()
        store.keyboardPane = .records
        if panel.isMiniaturized {
            panel.deminiaturize(nil)
        }

        NSRunningApplication.current.activate(
            options: [.activateAllWindows, .activateIgnoringOtherApps]
        )
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()

        if let attachedSheet = panel.attachedSheet {
            attachedSheet.orderFrontRegardless()
            attachedSheet.makeKey()
            return
        }

        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panel.makeKey()
            NotificationCenter.default.post(name: .benriClearSearchFocus, object: nil)
            self.panel.makeFirstResponder(self.panel)
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
        cancelPendingPaste()
        guard !isHidingPanel else { return }
        isHidingPanel = true
        defer { isHidingPanel = false }
        store.flushPendingRecordSave()

        if let attachedSheet = panel.attachedSheet {
            let applicationToRestore = shouldRestore ? previousApplication : nil
            previousApplication = nil
            previousFocusedElement = nil
            attachedSheet.orderOut(nil)
            panel.orderOut(nil)

            if let applicationToRestore, !applicationToRestore.isTerminated {
                applicationToRestore.activate(
                    options: [.activateAllWindows, .activateIgnoringOtherApps]
                )
            }
            return
        }

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

        guard !previousApplication.isTerminated else { return }
        guard shouldPaste, canPaste else {
            if shouldPaste, !canPaste {
                pasteLogger.error(
                    "Accessibility permission unavailable; clipboard copy kept, automatic paste cancelled"
                )
            }
            previousApplication.activate(
                options: [.activateAllWindows, .activateIgnoringOtherApps]
            )
            return
        }

        startPasteTransaction(
            into: previousApplication,
            focusedElement: focusedElement
        )
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide(restoringPreviousApplication: true)
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        guard panel.isVisible, !isHidingPanel else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.panel.isVisible,
                  !self.panel.isKeyWindow,
                  self.panel.attachedSheet == nil,
                  !self.isHidingPanel
            else { return }

            pasteLogger.debug("Panel resigned key; hiding")
            self.hide(restoringPreviousApplication: false)
        }
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

    private func startPasteTransaction(
        into application: NSRunningApplication,
        focusedElement: AXUIElement?
    ) {
        cancelPendingPaste()
        let transactionID = pasteTransactionID
        pasteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runPasteTransaction(
                transactionID: transactionID,
                application: application,
                focusedElement: focusedElement
            )
            if self.pasteTransactionID == transactionID {
                self.pasteTask = nil
            }
        }
    }

    private func runPasteTransaction(
        transactionID: UInt64,
        application: NSRunningApplication,
        focusedElement: AXUIElement?
    ) async {
        guard isPasteTransactionCurrent(transactionID), !application.isTerminated else { return }

        if !isPasteTargetActive(application) {
            application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])

            for _ in 0..<20 {
                guard await waitForPasteDelay(
                    nanoseconds: 50_000_000,
                    transactionID: transactionID
                ) else { return }
                if isPasteTargetActive(application) {
                    break
                }
            }
        }

        guard isPasteTargetActive(application) else {
            pasteLogger.error("Target application did not become active; paste cancelled")
            return
        }

        guard await waitForPasteDelay(
            nanoseconds: 80_000_000,
            transactionID: transactionID
        ) else { return }
        guard isPasteTargetActive(application) else {
            pasteLogger.error("Target application changed before focus restore; paste cancelled")
            return
        }

        guard restoreFocus(focusedElement, into: application) else { return }

        guard await waitForPasteDelay(
            nanoseconds: 50_000_000,
            transactionID: transactionID
        ) else { return }
        guard isPasteTargetActive(application) else {
            pasteLogger.error("Target application changed before Command-V; paste cancelled")
            return
        }

        await postPasteShortcut(
            into: application,
            transactionID: transactionID
        )
    }

    private func restoreFocus(
        _ focusedElement: AXUIElement?,
        into application: NSRunningApplication
    ) -> Bool {
        guard isPasteTargetActive(application) else {
            pasteLogger.error("Paste target changed before focus preparation; paste cancelled")
            return false
        }

        guard let focusedElement else {
            pasteLogger.info(
                "No captured AX element; target remains active, using its current responder"
            )
            return true
        }

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

        if applicationFocusResult == .success || elementFocusResult == .success {
            return isPasteTargetActive(application)
        }

        guard isPasteTargetActive(application) else {
            pasteLogger.error("Paste target changed after focus restore failed; paste cancelled")
            return false
        }

        pasteLogger.info(
            "Unable to restore captured focus; target remains active, using its current responder"
        )
        return true
    }

    private func postPasteShortcut(
        into application: NSRunningApplication,
        transactionID: UInt64
    ) async {
        guard isPasteTransactionCurrent(transactionID), isPasteTargetActive(application) else {
            pasteLogger.error("Paste target is no longer active; Command-V cancelled")
            return
        }

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
            guard isPasteTransactionCurrent(transactionID), isPasteTargetActive(application) else {
                return
            }
            runAppleScriptPaste()
            return
        }

        source.localEventsSuppressionInterval = 0
        valueDown.flags = .maskCommand
        valueUp.flags = .maskCommand
        valueDown.post(tap: .cghidEventTap)

        do {
            try await Task.sleep(nanoseconds: 20_000_000)
        } catch {
            valueUp.post(tap: .cghidEventTap)
            return
        }

        valueUp.post(tap: .cghidEventTap)
        pasteLogger.info("Posted Command-V events")
    }

    private func waitForPasteDelay(
        nanoseconds: UInt64,
        transactionID: UInt64
    ) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
        } catch {
            return false
        }
        return isPasteTransactionCurrent(transactionID)
    }

    private func isPasteTransactionCurrent(_ transactionID: UInt64) -> Bool {
        transactionID == pasteTransactionID && !Task.isCancelled
    }

    private func isPasteTargetActive(_ application: NSRunningApplication) -> Bool {
        guard !application.isTerminated, application.isActive else { return false }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier
            == application.processIdentifier
    }

    private func cancelPendingPaste() {
        pasteTransactionID &+= 1
        pasteTask?.cancel()
        pasteTask = nil
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

    private func updatePanelWidth(
        for mode: RecordPanelMode,
        hasFatalError: Bool
    ) {
        let targetWidth = !hasFatalError && mode == .closed
            ? VaultLayout.collapsedWindowWidth
            : VaultLayout.expandedWindowWidth
        let targetMinimumSize = NSSize(
            width: targetWidth,
            height: VaultLayout.windowHeight
        )

        if targetWidth < panel.contentMinSize.width {
            panel.contentMinSize = targetMinimumSize
        }

        guard abs(panel.frame.width - targetWidth) > 0.5 else {
            panel.contentMinSize = targetMinimumSize
            return
        }

        var frame = panel.frame
        frame.size.width = targetWidth
        panel.setFrame(frame, display: false)
        panel.contentMinSize = targetMinimumSize
    }

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let panelSize = NSSize(
            width: panel.frame.width,
            height: VaultLayout.windowHeight
        )
        let origin = NSPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.midY - panelSize.height / 2
        )
        panel.setFrame(
            NSRect(origin: origin, size: panelSize),
            display: false
        )
    }
}
