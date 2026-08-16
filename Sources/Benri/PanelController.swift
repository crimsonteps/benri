import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import BenriCore
import OSLog
import SwiftUI

private let pasteLogger = Logger(
    subsystem: "com.crimsonteps.benri",
    category: "Paste"
)

extension Notification.Name {
    static let benriFocusSearch = Notification.Name("Benri.FocusSearch")
    static let benriClearSearchFocus = Notification.Name("Benri.ClearSearchFocus")
    static let benriSaveActiveEditor = Notification.Name("Benri.SaveActiveEditor")
    static let benriCancelActiveEditor = Notification.Name("Benri.CancelActiveEditor")
    static let benriActivateActionMenu = Notification.Name("Benri.ActivateActionMenu")
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
    private let clipboardStore: ClipboardStore
    private let paletteState: PaletteState
    private let clipboardManager: ClipboardManager
    private var keyMonitor: Any?
    private var shouldHideAfterEditorDismissal = false
    private var isHidingPanel = false
    private var isPastingWhileKeepingPanelOpen = false
    private var previousApplication: NSRunningApplication?
    private var previousFocusedElement: AXUIElement?
    private var pasteTask: Task<Void, Never>?
    private var pasteTransactionID: UInt64 = 0
    private var cancellables = Set<AnyCancellable>()
    private let recordContextMenuAnchor = RecordContextMenuAnchor()

    var shouldHideWhenApplicationResigns: Bool {
        !isPastingWhileKeepingPanelOpen
    }

    init(
        store: VaultViewModel,
        clipboardStore: ClipboardStore,
        paletteState: PaletteState,
        clipboardManager: ClipboardManager,
        settings: AppSettings,
        openSettings: @escaping () -> Void
    ) {
        self.store = store
        self.clipboardStore = clipboardStore
        self.paletteState = paletteState
        self.clipboardManager = clipboardManager
        self.panel = BenriPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: VaultLayout.collapsedWindowWidth,
                height: VaultLayout.windowHeight
            ),
            styleMask: [
                .borderless,
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "Benri"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // The palette draws its own rounded shadow. NSPanel's native shadow
        // follows the rectangular borderless window and exposes square corners.
        panel.hasShadow = false
        panel.contentMinSize = NSSize(
            width: VaultLayout.collapsedWindowWidth,
            height: VaultLayout.windowHeight
        )
        let rootView = VaultPanelView(
            store: store,
            clipboardStore: clipboardStore,
            paletteState: paletteState,
            settings: settings,
            clipboardManager: clipboardManager,
            openSettings: openSettings,
            onClose: { [weak self] in
                self?.hide(restoringPreviousApplication: true)
            },
            onPasteRecord: { [weak self] recordID in
                self?.copyRecordAndPaste(recordID)
            },
            onPasteClipboard: { [weak self] item in
                self?.copyClipboardAndPaste(item)
            },
            onCopyClipboard: { [weak self] item in
                self?.copyClipboard(item)
            },
            onPasteClipboardKeepingOpen: { [weak self] item in
                self?.pasteClipboardKeepingPanelOpen(item)
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
            self?.handleKeyDown(event) ?? event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard panel.isKeyWindow || panel.attachedSheet?.isKeyWindow == true,
              store.alert == nil,
              paletteState.confirmation == nil
        else { return event }

        // Let an input method finish or navigate its marked text before Benri
        // interprets Return, Escape, or arrow keys as application commands.
        if activeTextView?.hasMarkedText() == true {
            return event
        }

        if handleActiveEditorShortcut(event) {
            return nil
        }
        guard panel.attachedSheet == nil else { return event }

        let initialModifiers = shortcutModifiers(for: event)
        let initialKeyCode = Int(event.keyCode)
        if initialModifiers == [.command], initialKeyCode == kVK_ANSI_K {
            paletteState.toggleActionMenu(actions: availablePaletteActions)
            return nil
        }
        if paletteState.actionMenuOpen {
            return handleActionMenuKeyDown(event)
        }
        if Int(event.keyCode) == kVK_Tab, initialModifiers.isEmpty {
            paletteState.toggleMode()
            if paletteState.mode == .clipboard {
                paletteState.ensureClipboardSelection(in: clipboardStore)
            } else {
                store.ensureSelection()
            }
            return nil
        }
        if paletteState.mode == .clipboard {
            return handleClipboardKeyDown(event)
        }

        let modifiers = shortcutModifiers(for: event)
        let keyCode = Int(event.keyCode)

        if modifiers == [.command] {
            switch keyCode {
            case kVK_ANSI_F:
                focusSearchFromKeyboard()
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if store.recordPanelMode == .edit {
                    return finishInlineRecordEditing() ? nil : event
                }
                return store.copySelectedRecord() ? nil : event
            case kVK_ANSI_E:
                guard !preservesNativeTextEditingCommands else { return event }
                return editKeyboardSelection() ? nil : event
            case kVK_Delete, kVK_ForwardDelete:
                guard !preservesNativeTextEditingCommands else { return event }
                return deleteKeyboardSelection() ? nil : event
            case kVK_ANSI_C:
                guard !shouldUseNativeCopy else { return event }
                guard store.keyboardPane != .categories,
                      store.copySelectedRecord()
                else { return event }
                return nil
            case kVK_ANSI_S:
                return finishInlineRecordEditing() ? nil : event
            default:
                break
            }
        }

        if modifiers == [.control],
           keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter {
            return showKeyboardActionMenu() ? nil : event
        }

        if modifiers == [.shift], keyCode == kVK_F10 {
            return showKeyboardActionMenu() ? nil : event
        }

        if modifiers.isEmpty, keyCode == kVK_Escape {
            if store.recordPanelMode == .edit {
                return finishInlineRecordEditing() ? nil : event
            }
            if store.recordPanelMode == .preview {
                store.closeRecordPanel()
                restorePanelResponder()
                return nil
            }
            if store.isSearchFocused {
                NotificationCenter.default.post(name: .benriClearSearchFocus, object: nil)
                store.setSearchFocused(false)
                restorePanelResponder()
                return nil
            }
            hide(restoringPreviousApplication: true)
            return nil
        }

        // Inline record editing owns all ordinary text-navigation and editing
        // keys, even during a brief first-responder transition.
        guard store.recordPanelMode != .edit else { return event }

        // Search uses the field editor, including arrows and Return for IME and
        // native text behavior. Escape and explicit app commands were handled above.
        guard !store.isSearchFocused else { return event }
        guard modifiers.isEmpty else { return event }

        switch keyCode {
        case kVK_UpArrow:
            switch store.keyboardPane {
            case .categories:
                store.moveCategorySelection(-1)
            case .records:
                panel.makeFirstResponder(nil)
                store.moveSelection(-1)
            case .value:
                return event
            }
            return nil
        case kVK_DownArrow:
            switch store.keyboardPane {
            case .categories:
                store.moveCategorySelection(1)
            case .records:
                panel.makeFirstResponder(nil)
                store.moveSelection(1)
            case .value:
                return event
            }
            return nil
        case kVK_LeftArrow:
            store.moveKeyboardPaneLeft()
            restorePanelResponder()
            return nil
        case kVK_RightArrow:
            panel.makeFirstResponder(nil)
            store.moveKeyboardPaneRight()
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if store.keyboardPane != .categories,
               copyRecordAndPaste() {
                return nil
            }
            return event
        default:
            return event
        }
    }

    private func handleClipboardKeyDown(_ event: NSEvent) -> NSEvent? {
        let modifiers = shortcutModifiers(for: event)
        let keyCode = Int(event.keyCode)

        if modifiers == [.command] {
            switch keyCode {
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if let item = paletteState.selectedClipboardItem(in: clipboardStore) {
                    copyClipboard(item)
                    return nil
                }
            case kVK_ANSI_Period:
                if let item = paletteState.selectedClipboardItem(in: clipboardStore) {
                    clipboardStore.togglePinned(item)
                    paletteState.ensureClipboardSelection(in: clipboardStore)
                    return nil
                }
            case kVK_Delete, kVK_ForwardDelete:
                if let item = paletteState.selectedClipboardItem(in: clipboardStore) {
                    paletteState.confirmation = .deleteClipboard(item.id)
                    return nil
                }
            case kVK_ANSI_F:
                focusSearchFromKeyboard()
                return nil
            default:
                break
            }
        }

        if modifiers == [.option],
           keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter,
           let item = paletteState.selectedClipboardItem(in: clipboardStore) {
            pasteClipboardKeepingPanelOpen(item)
            return nil
        }

        if modifiers == [.control], keyCode == kVK_ANSI_X {
            if let item = paletteState.selectedClipboardItem(in: clipboardStore) {
                paletteState.confirmation = .deleteClipboard(item.id)
            }
            return nil
        }

        if modifiers == [.control, .shift], keyCode == kVK_ANSI_X {
            paletteState.confirmation = .clearClipboard
            return nil
        }

        guard modifiers.isEmpty else { return event }
        switch keyCode {
        case kVK_UpArrow:
            paletteState.moveClipboardSelection(-1, in: clipboardStore)
            return nil
        case kVK_DownArrow:
            paletteState.moveClipboardSelection(1, in: clipboardStore)
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = paletteState.selectedClipboardItem(in: clipboardStore) {
                copyClipboardAndPaste(item)
                return nil
            }
        case kVK_Escape:
            hide(restoringPreviousApplication: true)
            return nil
        default:
            return event
        }
        return event
    }

    @discardableResult
    private func copyRecordAndPaste(_ recordID: UUID? = nil) -> Bool {
        guard store.recordPanelMode != .edit else { return false }
        if let recordID {
            store.selectRecord(recordID)
        }
        guard let content = store.selectedRecord?.content,
              !content.isEmpty,
              clipboardManager.writeText(content)
        else { return false }

        pasteLogger.info("Record requested paste")
        hide(
            restoringPreviousApplication: true,
            pastingIntoPreviousApplication: true
        )
        return true
    }

    @discardableResult
    private func copyClipboard(_ item: ClipboardItem) -> Bool {
        clipboardManager.write(item)
    }

    @discardableResult
    private func copyClipboardAndPaste(_ item: ClipboardItem) -> Bool {
        guard clipboardManager.write(item) else { return false }
        clipboardStore.promote(item)
        pasteLogger.info("Clipboard history item requested paste")
        hide(
            restoringPreviousApplication: true,
            pastingIntoPreviousApplication: true
        )
        return true
    }

    @discardableResult
    private func pasteClipboardKeepingPanelOpen(_ item: ClipboardItem) -> Bool {
        guard clipboardManager.write(item),
              let previousApplication,
              !previousApplication.isTerminated,
              accessibilityPermissionGranted(prompt: true)
        else { return false }
        clipboardStore.promote(item)
        cancelPendingPaste()
        isPastingWhileKeepingPanelOpen = true
        let transactionID = pasteTransactionID
        let focusedElement = previousFocusedElement
        pasteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runPasteTransaction(
                transactionID: transactionID,
                application: previousApplication,
                focusedElement: focusedElement
            )
            guard self.pasteTransactionID == transactionID else { return }
            self.pasteTask = nil
            self.isPastingWhileKeepingPanelOpen = false
            NSRunningApplication.current.activate(
                options: [.activateAllWindows, .activateIgnoringOtherApps]
            )
            self.panel.orderFrontRegardless()
            self.panel.makeKeyAndOrderFront(nil)
        }
        return true
    }

    private var availablePaletteActions: [PaletteAction] {
        PaletteAction.available(
            mode: paletteState.mode,
            record: store.selectedRecord,
            clipboardItem: paletteState.selectedClipboardItem(in: clipboardStore)
        )
    }

    private func handleActionMenuKeyDown(_ event: NSEvent) -> NSEvent? {
        let modifiers = shortcutModifiers(for: event)
        let keyCode = Int(event.keyCode)

        if modifiers == [.command],
           keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter {
            paletteState.closeActionMenu()
            switch paletteState.mode {
            case .commonText:
                _ = store.copySelectedRecord()
            case .clipboard:
                if let item = paletteState.selectedClipboardItem(in: clipboardStore) {
                    _ = copyClipboard(item)
                }
            }
            return nil
        }

        if modifiers == [.option],
           keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter,
           let item = paletteState.selectedClipboardItem(in: clipboardStore) {
            paletteState.closeActionMenu()
            _ = pasteClipboardKeepingPanelOpen(item)
            return nil
        }

        guard modifiers.isEmpty else { return nil }
        switch keyCode {
        case kVK_UpArrow:
            paletteState.moveActionMenuSelection(-1, actions: availablePaletteActions)
        case kVK_DownArrow:
            paletteState.moveActionMenuSelection(1, actions: availablePaletteActions)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            NotificationCenter.default.post(name: .benriActivateActionMenu, object: nil)
        case kVK_Escape:
            paletteState.closeActionMenu()
        default:
            break
        }
        return nil
    }

    private func handleActiveEditorShortcut(_ event: NSEvent) -> Bool {
        guard panel.attachedSheet?.isKeyWindow == true else { return false }

        let hasActiveEditor = store.recordEditor != nil || store.categoryEditor != nil
        guard hasActiveEditor else { return false }

        let modifiers = shortcutModifiers(for: event)
        if event.keyCode == kVK_Escape, modifiers.isEmpty {
            NotificationCenter.default.post(name: .benriCancelActiveEditor, object: nil)
            return true
        }

        guard modifiers == [.command] else { return false }
        switch Int(event.keyCode) {
        case kVK_ANSI_S, kVK_Return, kVK_ANSI_KeypadEnter:
            NotificationCenter.default.post(name: .benriSaveActiveEditor, object: nil)
            return true
        default:
            return false
        }
    }

    private func shortcutModifiers(for event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection([.command, .option, .control, .shift])
    }

    private var activeTextView: NSTextView? {
        if let textView = panel.attachedSheet?.firstResponder as? NSTextView {
            return textView
        }
        return panel.firstResponder as? NSTextView
    }

    private var preservesNativeTextEditingCommands: Bool {
        panel.attachedSheet != nil
            || store.recordPanelMode == .edit
            || store.isSearchFocused
            || activeTextView?.isEditable == true
    }

    private var shouldUseNativeCopy: Bool {
        if preservesNativeTextEditingCommands {
            return true
        }
        guard let textView = activeTextView else { return false }
        let selectedRange = textView.selectedRange()
        return selectedRange.location != NSNotFound && selectedRange.length > 0
    }

    @discardableResult
    private func finishInlineRecordEditing() -> Bool {
        guard store.recordPanelMode == .edit else { return false }
        panel.makeFirstResponder(nil)
        guard store.finishInlineRecordEditing() else { return false }
        restorePanelResponder()
        return true
    }

    private func restorePanelResponder() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isKeyWindow else { return }
            self.panel.makeFirstResponder(self.panel)
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

    var canShowKeyboardActionMenu: Bool {
        canUseKeyboardSelectionActions && store.keyboardActionTarget != nil
    }

    var canPresentEditorFromKeyboard: Bool {
        panel.attachedSheet == nil && store.alert == nil && store.canModifyVault
    }

    var canFocusSearchFromKeyboard: Bool {
        panel.attachedSheet == nil && store.alert == nil
    }

    var canEditKeyboardSelection: Bool {
        canUseKeyboardSelectionActions && store.canEditKeyboardSelection
    }

    var canDeleteKeyboardSelection: Bool {
        canUseKeyboardSelectionActions && store.canDeleteKeyboardSelection
    }

    private var canUseKeyboardSelectionActions: Bool {
        panel.isVisible
            && panel.attachedSheet == nil
            && store.alert == nil
            && store.recordPanelMode != .edit
            && !store.isSearchFocused
            && activeTextView?.isEditable != true
    }

    func focusSearchFromKeyboard() {
        guard canFocusSearchFromKeyboard else { return }
        show()
        store.closeRecordPanel()
        store.activateRecordNavigation()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible, self.panel.attachedSheet == nil else { return }
            NotificationCenter.default.post(name: .benriFocusSearch, object: nil)
        }
    }

    @discardableResult
    func showKeyboardActionMenu() -> Bool {
        guard canShowKeyboardActionMenu,
              let target = store.keyboardActionTarget,
              let contentView = panel.contentView
        else { return false }

        let menu = NSMenu()
        menu.autoenablesItems = false

        switch target {
        case .category:
            let editItem = NSMenuItem(
                title: "编辑分类",
                action: #selector(editFromKeyboardActionMenu(_:)),
                keyEquivalent: ""
            )
            editItem.target = self
            editItem.isEnabled = store.canEditKeyboardSelection
            menu.addItem(editItem)

            let deleteItem = NSMenuItem(
                title: "删除分类",
                action: #selector(deleteFromKeyboardActionMenu(_:)),
                keyEquivalent: ""
            )
            deleteItem.target = self
            deleteItem.isEnabled = store.canDeleteKeyboardSelection
            menu.addItem(deleteItem)
        case .record:
            let editItem = NSMenuItem(
                title: "编辑",
                action: #selector(editFromKeyboardActionMenu(_:)),
                keyEquivalent: ""
            )
            editItem.target = self
            editItem.isEnabled = store.canEditKeyboardSelection
            menu.addItem(editItem)

            let deleteItem = NSMenuItem(
                title: "删除",
                action: #selector(deleteFromKeyboardActionMenu(_:)),
                keyEquivalent: ""
            )
            deleteItem.target = self
            deleteItem.isEnabled = store.canDeleteKeyboardSelection
            menu.addItem(deleteItem)
        }

        if case .record = target,
           let anchorView = recordContextMenuAnchor.selectedView,
           anchorView.window === panel {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: anchorView.bounds.maxX - 6, y: anchorView.bounds.midY),
                in: anchorView
            )
            return true
        }

        let anchorX: CGFloat
        switch target {
        case .category:
            anchorX = VaultLayout.windowInset + VaultLayout.categoryWidth - 4
        case .record:
            anchorX = VaultLayout.collapsedWindowWidth - VaultLayout.windowInset - 6
        }
        let anchorY = contentView.isFlipped
            ? contentView.bounds.maxY - VaultLayout.windowInset - 48
            : VaultLayout.windowInset + 48

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: anchorX, y: anchorY),
            in: contentView
        )
        return true
    }

    @discardableResult
    func editKeyboardSelection() -> Bool {
        guard canEditKeyboardSelection else { return false }
        panel.makeFirstResponder(nil)
        return store.beginEditingKeyboardSelection()
    }

    @discardableResult
    func deleteKeyboardSelection() -> Bool {
        guard canDeleteKeyboardSelection else { return false }
        panel.makeFirstResponder(nil)
        return store.requestDeleteKeyboardSelection()
    }

    @objc private func editFromKeyboardActionMenu(_ sender: Any?) {
        editKeyboardSelection()
    }

    @objc private func deleteFromKeyboardActionMenu(_ sender: Any?) {
        deleteKeyboardSelection()
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
        paletteState.closeActionMenu()

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
        if paletteState.mode == .commonText {
            store.activateRecordNavigation()
        } else {
            paletteState.ensureClipboardSelection(in: clipboardStore)
        }
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
        paletteState.closeActionMenu()
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
        guard panel.isVisible,
              !isHidingPanel,
              !isPastingWhileKeepingPanelOpen
        else { return }

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
        let targetWidth = VaultLayout.expandedWindowWidth
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
