import AppKit
import Foundation
import BenriCore
import SwiftUI

@MainActor
func releasePanelEditingFocus() {
    NSApp.keyWindow?.makeFirstResponder(nil)
}

enum VaultLayout {
    static let collapsedWindowWidth: CGFloat = 820
    static let expandedWindowWidth: CGFloat = 820
    static let windowHeight: CGFloat = 500
    static let windowInset: CGFloat = 10
    static let columnSpacing: CGFloat = 10
    static let categoryWidth: CGFloat = 58
    static let recordListWidth: CGFloat = 300
    static let navigationCornerRadius = BenriTheme.Radius.panel
    static let contentCornerRadius = BenriTheme.Radius.contentPanel
    static let previewMinimumHeight: CGFloat = 160
    static let contentPanelMaximumHeight = windowHeight - windowInset * 3
}

struct VaultPanelView: View {
    @ObservedObject var store: VaultViewModel
    @ObservedObject var clipboardStore: ClipboardStore
    @ObservedObject var paletteState: PaletteState
    @ObservedObject var settings: AppSettings
    let clipboardManager: ClipboardManager
    let openSettings: () -> Void
    let onClose: () -> Void
    let onPasteRecord: (UUID) -> Void
    let onPasteClipboard: (ClipboardItem) -> Void
    let onCopyClipboard: (ClipboardItem) -> Void
    let onPasteClipboardKeepingOpen: (ClipboardItem) -> Void
    let onEditorDismissed: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        Group {
            if let fatalErrorMessage = store.fatalErrorMessage {
                VaultFailureView(
                    message: fatalErrorMessage,
                    openDataFolder: store.openDataFolder,
                    resetVault: store.requestReset
                )
                .benriPaletteSurface(cornerRadius: VaultLayout.contentCornerRadius)
                .padding(VaultLayout.windowInset)
                .ignoresSafeArea()
            } else {
                commandContent
            }
        }
        .frame(
            minWidth: VaultLayout.collapsedWindowWidth,
            minHeight: VaultLayout.windowHeight
        )
        .background(Color.clear)
        .onAppear {
            store.ensureSelection()
        }
        .onExitCommand(perform: onClose)
        .sheet(item: $store.recordEditor, onDismiss: onEditorDismissed) { context in
            RecordEditorView(store: store, context: context)
                .benriSheetBackground()
        }
        .alert(item: $store.alert) { alert in
            makeAlert(alert)
        }
        .onChange(of: paletteState.mode) { mode in
            if mode == .clipboard, !settings.hasConfirmedClipboardHistory {
                paletteState.confirmation = .enableClipboard
            }
            focusSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .benriFocusSearch)) { _ in
            focusSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .benriClearSearchFocus)) { _ in
            searchFocused = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .benriActivateActionMenu)) { _ in
            guard let action = paletteState.selectedAction(in: availableActions) else { return }
            perform(action)
        }
    }

    private var commandContent: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                Group {
                    switch paletteState.mode {
                    case .commonText:
                        CommonTextPaletteView(
                            store: store,
                            onPaste: onPasteRecord,
                            onActions: openRecordActions
                        )
                    case .clipboard:
                        ClipboardPaletteView(
                            store: clipboardStore,
                            state: paletteState,
                            onPaste: onPasteClipboard,
                            onActions: openClipboardActions
                        )
                    }
                }
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                footer
            }

            if paletteState.actionMenuOpen {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { paletteState.closeActionMenu() }

                actionMenu
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(8)
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.96, anchor: .bottomTrailing)
                        )
                    )
            }

            if let confirmation = paletteState.confirmation {
                confirmationOverlay(confirmation)
            }
        }
        .benriCommandSurface(cornerRadius: 26)
        .padding(10)
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.14), value: paletteState.actionMenuOpen)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                paletteState.toggleMode()
            } label: {
                Image(systemName: paletteState.mode == .commonText ? "text.quote" : "doc.on.clipboard")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.62))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("切换常用文本与剪贴板 Tab")

            TextField(searchPrompt, text: searchBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.primary.opacity(0.92))
                .tint(.accentColor)
                .focused($searchFocused)
                .onSubmit(performPrimaryAction)
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: openSettings) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary.opacity(0.68))
            .help("设置 ⌘,")

            Text("Tab 切换")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.30))

            Spacer()

            if !primaryItemMissing {
                HStack(spacing: 2) {
                    footerActionButton(action: performPrimaryAction) {
                        HStack(spacing: 7) {
                            Text("粘贴")
                            PaletteShortcutView(shortcut: "↵")
                        }
                    }

                    footerActionButton(action: toggleActionMenu) {
                        HStack(spacing: 7) {
                            Text("操作")
                            PaletteShortcutView(shortcut: "⌘K")
                        }
                        .foregroundStyle(Color.primary.opacity(0.64))
                    }
                }
                .padding(4)
                .background(Color.primary.opacity(0.10), in: Capsule())
                .overlay {
                    Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    private func footerActionButton<Label: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 11)
                .frame(height: 28)
        }
        .buttonStyle(.plain)
    }

    private var availableActions: [PaletteAction] {
        PaletteAction.available(
            mode: paletteState.mode,
            record: store.selectedRecord,
            clipboardItem: paletteState.selectedClipboardItem(in: clipboardStore)
        )
    }

    private var actionMenu: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let header = actionMenuHeader {
                Text(header)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.48))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
            }

            ForEach(Array(availableActions.enumerated()), id: \.element.id) { index, action in
                PaletteActionRow(
                    title: actionTitle(action),
                    systemImage: actionIcon(action),
                    shortcut: actionShortcut(action),
                    destructive: actionIsDestructive(action),
                    selected: index == paletteState.actionMenuSelection,
                    onHover: { paletteState.actionMenuSelection = index },
                    onActivate: {
                        paletteState.actionMenuSelection = index
                        perform(action)
                    }
                )
            }
        }
        .padding(6)
        .frame(width: 276)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
    }

    private var searchBinding: Binding<String> {
        paletteState.mode == .commonText
            ? $store.searchText
            : $paletteState.clipboardQuery
    }

    private var searchPrompt: String {
        paletteState.mode == .commonText ? "搜索常用文本…" : "筛选剪贴板历史…"
    }

    private var primaryItemMissing: Bool {
        switch paletteState.mode {
        case .commonText: store.selectedRecord?.content.isEmpty != false
        case .clipboard: paletteState.selectedClipboardItem(in: clipboardStore) == nil
        }
    }

    private func performPrimaryAction() {
        switch paletteState.mode {
        case .commonText:
            if let id = store.selectedRecordID { onPasteRecord(id) }
        case .clipboard:
            if let item = paletteState.selectedClipboardItem(in: clipboardStore) {
                onPasteClipboard(item)
            }
        }
    }

    private func toggleActionMenu() {
        paletteState.toggleActionMenu(actions: availableActions)
    }

    private func openRecordActions(_ record: VaultRecord) {
        store.selectRecord(record.id)
        paletteState.openActionMenu(
            actions: PaletteAction.available(
                mode: .commonText,
                record: record,
                clipboardItem: nil
            )
        )
    }

    private func openClipboardActions(_ item: ClipboardItem) {
        paletteState.selectedClipboardID = item.id
        paletteState.openActionMenu(
            actions: PaletteAction.available(
                mode: .clipboard,
                record: nil,
                clipboardItem: item
            )
        )
    }

    private var actionMenuHeader: String? {
        switch paletteState.mode {
        case .commonText:
            return store.selectedRecord?.name
        case .clipboard:
            guard let item = paletteState.selectedClipboardItem(in: clipboardStore) else {
                return nil
            }
            if item.kind == .image { return "图片" }
            let singleLine = (item.text ?? "")
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            return String(singleLine.prefix(40))
        }
    }

    private func perform(_ action: PaletteAction) {
        paletteState.closeActionMenu()
        switch action {
        case .paste:
            performPrimaryAction()
        case .copy:
            switch paletteState.mode {
            case .commonText:
                if let content = store.selectedRecord?.content, !content.isEmpty {
                    _ = clipboardManager.writeText(content)
                }
            case .clipboard:
                if let item = paletteState.selectedClipboardItem(in: clipboardStore) {
                    onCopyClipboard(item)
                }
            }
        case .pasteKeepingOpen:
            if let item = paletteState.selectedClipboardItem(in: clipboardStore) {
                onPasteClipboardKeepingOpen(item)
            }
        case .editRecord:
            if let id = store.selectedRecordID { store.beginEditingRecord(id) }
        case .togglePin:
            if let item = paletteState.selectedClipboardItem(in: clipboardStore) {
                clipboardStore.togglePinned(item)
                paletteState.ensureClipboardSelection(in: clipboardStore)
            }
        case .revealImage:
            if let item = paletteState.selectedClipboardItem(in: clipboardStore),
               let url = clipboardStore.imageURL(for: item) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        case .deleteRecord:
            if let id = store.selectedRecordID { store.requestDeleteRecord(id) }
        case .deleteClipboard:
            if let item = paletteState.selectedClipboardItem(in: clipboardStore) {
                paletteState.confirmation = .deleteClipboard(item.id)
            }
        case .clearClipboard:
            paletteState.confirmation = .clearClipboard
        }
    }

    private func actionTitle(_ action: PaletteAction) -> String {
        switch action {
        case .paste: "粘贴"
        case .copy: "复制到剪贴板"
        case .pasteKeepingOpen: "粘贴并保持窗口打开"
        case .editRecord: "编辑"
        case .togglePin:
            paletteState.selectedClipboardItem(in: clipboardStore)?.isPinned == true
                ? "取消固定" : "固定"
        case .revealImage: "在 Finder 中显示"
        case .deleteRecord: "删除"
        case .deleteClipboard: "删除此记录"
        case .clearClipboard: "删除全部记录"
        }
    }

    private func actionIcon(_ action: PaletteAction) -> String {
        switch action {
        case .paste: "doc.on.clipboard"
        case .copy: "doc.on.doc"
        case .pasteKeepingOpen: "macwindow"
        case .editRecord: "pencil"
        case .togglePin:
            paletteState.selectedClipboardItem(in: clipboardStore)?.isPinned == true
                ? "pin.slash" : "pin"
        case .revealImage: "folder"
        case .deleteRecord, .deleteClipboard, .clearClipboard: "trash"
        }
    }

    private func actionShortcut(_ action: PaletteAction) -> String? {
        switch action {
        case .paste: "↵"
        case .copy: "⌘↵"
        case .pasteKeepingOpen: "⌥↵"
        case .editRecord: "⌘E"
        case .togglePin: "⌘."
        case .deleteRecord: "⌘⌫"
        case .deleteClipboard: "⌃X"
        case .clearClipboard: "⌃⇧X"
        case .revealImage: nil
        }
    }

    private func actionIsDestructive(_ action: PaletteAction) -> Bool {
        switch action {
        case .deleteRecord, .deleteClipboard, .clearClipboard: true
        default: false
        }
    }

    private func focusSearch() {
        searchFocused = true
        DispatchQueue.main.async {
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
    }

    private func confirmationOverlay(_ confirmation: PaletteConfirmation) -> some View {
        VStack(spacing: 14) {
            Image(systemName: confirmationIcon(confirmation))
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.primary.opacity(0.72))
            Text(confirmationTitle(confirmation))
                .font(.system(size: 17, weight: .semibold))
            Text(confirmationMessage(confirmation))
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
            HStack(spacing: 10) {
                Button("取消") { paletteState.confirmation = nil }
                Button(confirmationButton(confirmation), role: confirmation == .enableClipboard ? nil : .destructive) {
                    resolve(confirmation)
                }
            }
        }
        .padding(28)
        .frame(width: 390)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.24))
    }

    private func resolve(_ confirmation: PaletteConfirmation) {
        switch confirmation {
        case .enableClipboard:
            settings.hasConfirmedClipboardHistory = true
            settings.clipboardHistoryEnabled = true
            clipboardManager.updateMonitoring()
        case .clearClipboard:
            clipboardStore.clearAll()
        case let .deleteClipboard(id):
            if let item = clipboardStore.items.first(where: { $0.id == id }) {
                clipboardStore.remove(item)
            }
        }
        paletteState.confirmation = nil
    }

    private func confirmationTitle(_ confirmation: PaletteConfirmation) -> String {
        switch confirmation {
        case .enableClipboard: "启用剪贴板历史？"
        case .clearClipboard: "清空剪贴板历史？"
        case .deleteClipboard: "删除这条历史？"
        }
    }

    private func confirmationMessage(_ confirmation: PaletteConfirmation) -> String {
        switch confirmation {
        case .enableClipboard:
            "Benri 会在本机以明文缓存文本和图片，默认保留 90 天。可在设置中随时暂停或清空。"
        case .clearClipboard: "所有缓存文本和图片都会永久删除，此操作无法撤销。"
        case .deleteClipboard: "这条剪贴板记录会被永久删除。"
        }
    }

    private func confirmationIcon(_ confirmation: PaletteConfirmation) -> String {
        confirmation == .enableClipboard ? "doc.on.clipboard" : "trash"
    }

    private func confirmationButton(_ confirmation: PaletteConfirmation) -> String {
        confirmation == .enableClipboard ? "启用" : "删除"
    }

    private func makeAlert(_ alert: VaultAlert) -> Alert {
        switch alert {
        case let .saveError(message):
            return Alert(
                title: Text("无法保存"),
                message: Text(message),
                dismissButton: .default(Text("知道了"))
            )
        case .confirmReset:
            return Alert(
                title: Text("重置保险库？"),
                message: Text("现有加密数据和本机密钥都会被删除，此操作无法撤销。"),
                primaryButton: .destructive(Text("重置"), action: store.resetVault),
                secondaryButton: .cancel(Text("取消"))
            )
        case let .confirmDeleteRecord(id):
            return Alert(
                title: Text("删除记录？"),
                message: Text("这条记录将被永久删除。"),
                primaryButton: .destructive(Text("删除")) {
                    store.deleteRecord(id)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        case let .confirmDeleteCategory(id):
            return Alert(
                title: Text("删除分类？"),
                message: Text("分类中的记录会被移动到另一个可用分类。"),
                primaryButton: .destructive(Text("删除")) {
                    store.deleteCategory(id)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }
}

private struct PaletteActionRow: View {
    let title: String
    let systemImage: String
    let shortcut: String?
    let destructive: Bool
    let selected: Bool
    let onHover: () -> Void
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(destructive ? Color.red : Color.secondary)
                    .frame(width: 20, height: 20)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(destructive ? Color.red : Color.primary)
                Spacer(minLength: 6)
                if let shortcut {
                    PaletteShortcutView(shortcut: shortcut)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.10) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { if $0 { onHover() } }
    }
}

private struct PaletteShortcutView: View {
    let shortcut: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(shortcut.enumerated()), id: \.offset) { _, glyph in
                Text(String(glyph))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .frame(minWidth: 14, minHeight: 14)
                    .padding(.horizontal, 1)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                    }
            }
        }
    }
}

private struct VaultFailureView: View {
    let message: String
    let openDataFolder: () -> Void
    let resetVault: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.orange)
            Text("无法打开保险库")
                .font(.system(size: 20, weight: .bold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 10) {
                Button("打开数据目录", action: openDataFolder)
                Button("重置保险库", role: .destructive, action: resetVault)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
