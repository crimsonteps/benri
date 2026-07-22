import AppKit
import Foundation
import QuickVaultCore
import SwiftUI

@MainActor
private func releasePanelEditingFocus() {
    NSApp.keyWindow?.makeFirstResponder(nil)
}

enum VaultLayout {
    static let collapsedWindowWidth: CGFloat = 340
    static let expandedWindowWidth: CGFloat = 820
    static let windowHeight: CGFloat = 520
    static let windowInset: CGFloat = 7
    static let columnSpacing: CGFloat = 8
    static let categoryWidth: CGFloat = 56
    static let recordListWidth: CGFloat = 268
    static let navigationCornerRadius: CGFloat = 18
    static let contentCornerRadius: CGFloat = 14
    static let previewMinimumHeight: CGFloat = 160
    static let contentPanelMaximumHeight = windowHeight - windowInset * 2
}

struct VaultPanelView: View {
    @ObservedObject var store: VaultViewModel
    @ObservedObject var settings: AppSettings
    let openSettings: () -> Void
    let onClose: () -> Void
    let onEditorDismissed: () -> Void

    private let sidebarExpanded = false

    private var showsRecordPanel: Bool {
        store.recordPanelMode != .closed
    }

    var body: some View {
        Group {
            if let fatalErrorMessage = store.fatalErrorMessage {
                VaultFailureView(
                    message: fatalErrorMessage,
                    openDataFolder: store.openDataFolder,
                    resetVault: store.requestReset
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: VaultLayout.contentCornerRadius,
                        style: .continuous
                    )
                )
                .quickVaultGlass(cornerRadius: VaultLayout.contentCornerRadius)
                .padding(VaultLayout.windowInset)
                .ignoresSafeArea()
            } else {
                mainContent
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
        }
        .sheet(item: $store.categoryEditor, onDismiss: onEditorDismissed) { context in
            CategoryEditorView(store: store, context: context)
        }
        .alert(item: $store.alert) { alert in
            makeAlert(alert)
        }
        .preferredColorScheme(settings.appearanceMode.colorScheme)
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: VaultLayout.columnSpacing) {
            HStack(spacing: 0) {
                SidebarView(
                    store: store,
                    isExpanded: sidebarExpanded,
                    openSettings: openSettings
                )
                .frame(width: sidebarExpanded ? 156 : VaultLayout.categoryWidth)

                Divider().opacity(0.28)

                RecordListView(store: store)
                    .frame(width: VaultLayout.recordListWidth)
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: VaultLayout.navigationCornerRadius,
                    style: .continuous
                )
            )
            .quickVaultGlass(cornerRadius: VaultLayout.navigationCornerRadius)

            if showsRecordPanel {
                RecordPanelView(store: store)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: store.recordPanelMode == .edit ? .infinity : nil,
                        alignment: .top
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: VaultLayout.contentCornerRadius,
                            style: .continuous
                        )
                    )
                    .quickVaultGlass(cornerRadius: VaultLayout.contentCornerRadius)
            }
        }
        .padding(VaultLayout.windowInset)
        .ignoresSafeArea()
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
        case let .confirmDeleteCategory(id):
            return Alert(
                title: Text("删除分类？"),
                message: Text("分类中的记录会被移动到“其他”。"),
                primaryButton: .destructive(Text("删除")) {
                    store.deleteCategory(id)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }
}

private struct SidebarView: View {
    private enum ScrollTarget: Hashable {
        case all
        case category(UUID)
    }

    @ObservedObject var store: VaultViewModel
    let isExpanded: Bool
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) {
                        SidebarRow(
                            title: "全部",
                            icon: "square.stack.3d.up.fill",
                            count: store.recordCount(for: nil),
                            isCustom: false,
                            isSelected: store.selectedCategoryID == nil,
                            isKeyboardActive: store.keyboardPane == .categories,
                            isExpanded: isExpanded
                        ) {
                            releasePanelEditingFocus()
                            store.selectCategory(nil)
                        }
                        .id(ScrollTarget.all)

                        ForEach(store.sortedCategories) { category in
                            SidebarRow(
                                title: category.name,
                                icon: iconName(for: category),
                                count: store.recordCount(for: category.id),
                                isCustom: !category.isBuiltIn,
                                isSelected: store.selectedCategoryID == category.id,
                                isKeyboardActive: store.keyboardPane == .categories,
                                isExpanded: isExpanded
                            ) {
                                releasePanelEditingFocus()
                                store.selectCategory(category.id)
                            }
                            .contextMenu {
                                if !category.isBuiltIn {
                                    Button("重命名") {
                                        store.beginRenamingCategory(category.id)
                                    }
                                    Button("删除分类", role: .destructive) {
                                        store.requestDeleteCategory(category.id)
                                    }
                                }
                            }
                            .id(ScrollTarget.category(category.id))
                        }
                    }
                    .padding(.horizontal, 7)
                }
                .onChange(of: store.selectedCategoryID) { selectedCategoryID in
                    let target = selectedCategoryID.map(ScrollTarget.category) ?? .all
                    proxy.scrollTo(target, anchor: .center)
                }
            }

            Spacer(minLength: 8)

            bottomActions
        }
        .background(Color.clear)
    }

    @ViewBuilder
    private var bottomActions: some View {
        Group {
            if isExpanded {
                HStack(spacing: 2) {
                    newCategoryButton
                    Spacer(minLength: 0)
                    settingsButton
                }
            } else {
                VStack(spacing: 2) {
                    newCategoryButton
                    settingsButton
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(7)
    }

    private var newCategoryButton: some View {
        Button(action: store.beginNewCategory) {
            Image(systemName: "plus")
                .frame(width: 28, height: 30)
        }
        .help("新建分类")
    }

    private var settingsButton: some View {
        Button(action: openSettings) {
            Image(systemName: "gearshape")
                .frame(width: 28, height: 30)
        }
        .help("设置 ⌘,")
    }

    private var header: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity)
            .padding(.top, 15)
            .padding(.bottom, 14)
    }

    private func iconName(for category: VaultCategory) -> String {
        switch category.id {
        case VaultDefaults.personalCategoryID:
            return "person.crop.circle"
        case VaultDefaults.workCategoryID:
            return "briefcase"
        case VaultDefaults.serverCategoryID:
            return "server.rack"
        case VaultDefaults.otherCategoryID:
            return "tray"
        default:
            return "folder"
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let icon: String
    let count: Int
    let isCustom: Bool
    let isSelected: Bool
    let isKeyboardActive: Bool
    let isExpanded: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 18)

                if isExpanded {
                    Text(title)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
            .padding(.horizontal, isExpanded ? 9 : 0)
            .frame(height: 36)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(rowBackground)
            }
        }
        .buttonStyle(.plain)
        .help("\(title)，\(count) 条记录")
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
    }

    private var accessibilityValue: String {
        isCustom ? "自定义分类，\(count) 条记录" : "\(count) 条记录"
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(isKeyboardActive ? 0.16 : 0.1)
        }
        return isHovering ? Color.primary.opacity(0.045) : Color.clear
    }
}

private struct RecordListView: View {
    @ObservedObject var store: VaultViewModel
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 12)
                .padding(.top, 11)
                .padding(.bottom, 8)

            if store.filteredRecords.isEmpty {
                RecordListEmptyView(hasQuery: !store.searchText.isEmpty) {
                    store.beginNewRecord()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(store.filteredRecords) { record in
                                RecordRow(
                                    record: record,
                                    categoryName: store.selectedCategoryID == nil
                                        ? store.categoryName(for: record.categoryID)
                                        : nil,
                                    isSelected: store.selectedRecordID == record.id,
                                    isKeyboardActive: store.keyboardPane == .records
                                ) {
                                    releasePanelEditingFocus()
                                    store.selectRecord(record.id)
                                } editAction: {
                                    releasePanelEditingFocus()
                                    store.beginEditingRecord(record.id)
                                } deleteAction: {
                                    store.deleteRecord(record.id)
                                }
                                .id(record.id)
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.bottom, 7)
                    }
                    .onChange(of: store.selectedRecordID) { selectedRecordID in
                        guard let selectedRecordID else { return }
                        proxy.scrollTo(selectedRecordID, anchor: .center)
                    }
                }
            }
        }
        .background(Color.clear)
        .onReceive(NotificationCenter.default.publisher(for: .quickVaultFocusSearch)) { _ in
            searchIsFocused = true
        }
        .onAppear {
            DispatchQueue.main.async {
                searchIsFocused = true
            }
        }
        .onChange(of: store.searchText) { _ in
            store.closeRecordPanel()
            store.keyboardPane = .records
            store.ensureSelection()
        }
        .onChange(of: store.selectedCategoryID) { _ in
            store.ensureSelection()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("搜索记录名称", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchIsFocused)
                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("清空搜索")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }

            Button(action: store.beginNewRecord) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut("n", modifiers: .command)
            .help("新建记录 ⌘N")
        }
    }
}

private struct RecordRow: View {
    let record: VaultRecord
    let categoryName: String?
    let isSelected: Bool
    let isKeyboardActive: Bool
    let action: () -> Void
    let editAction: () -> Void
    let deleteAction: () -> Void

    @State private var isHovering = false

    private var preview: String {
        let firstLine = record.content
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        return firstLine?.trimmingCharacters(in: .whitespaces) ?? "暂无内容"
    }

    private var subtitle: String {
        guard let categoryName else { return preview }
        return "\(categoryName) · \(preview)"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(rowBackground)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("编辑", action: editAction)
            Button("删除", role: .destructive, action: deleteAction)
        }
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(isKeyboardActive ? 0.16 : 0.1)
        }
        return isHovering ? Color.primary.opacity(0.04) : Color.clear
    }
}

private struct RecordListEmptyView: View {
    let hasQuery: Bool
    let createRecord: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: hasQuery ? "magnifyingglass" : "tray")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(hasQuery ? "没有匹配的记录" : "这里还没有记录")
                .font(.system(size: 13, weight: .semibold))
            if !hasQuery {
                Button("新建第一条记录", action: createRecord)
                    .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.secondary)
    }
}

private struct RecordPanelView: View {
    @ObservedObject var store: VaultViewModel

    @ViewBuilder
    var body: some View {
        if let record = store.selectedRecord {
            switch store.recordPanelMode {
            case .closed:
                EmptyView()
            case .preview:
                ReadOnlyRecordPreview(recordID: record.id, content: record.content)
            case .edit:
                recordEditor(record)
            }
        } else {
            EmptyView()
        }
    }

    private func recordEditor(_ record: VaultRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                InlineRecordNameEditor(store: store, record: record)
                    .id(record.id)

                Spacer(minLength: 12)

                Button {
                    store.copy(record.content)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(record.content.isEmpty)
                .help("复制内容")
            }
            .padding(.horizontal, 12)
            .frame(height: 44)

            InlineRecordContentEditor(store: store, record: record)
                .id(record.id)
        }
    }
}

private struct ReadOnlyRecordPreview: View {
    let recordID: UUID
    let content: String

    private var displayedContent: String {
        content.isEmpty ? "暂无内容" : content
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            previewText
                .frame(
                    minHeight: VaultLayout.previewMinimumHeight,
                    alignment: .topLeading
                )

            ScrollView(.vertical) {
                previewText
            }
            .frame(
                height: VaultLayout.contentPanelMaximumHeight,
                alignment: .top
            )
        }
        .id(recordID)
    }

    private var previewText: some View {
        Text(displayedContent)
            .font(.system(size: 14))
            .foregroundStyle(content.isEmpty ? Color.secondary : Color.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(14)
    }
}

private struct InlineRecordNameEditor: View {
    @ObservedObject var store: VaultViewModel
    let record: VaultRecord

    @State private var name: String
    @FocusState private var isFocused: Bool

    init(store: VaultViewModel, record: VaultRecord) {
        self.store = store
        self.record = record
        _name = State(initialValue: record.name)
    }

    var body: some View {
        TextField("记录名称", text: $name)
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .semibold))
            .lineLimit(1)
            .focused($isFocused)
            .onChange(of: name) { newValue in
                store.updateRecordName(id: record.id, name: newValue)
            }
            .onChange(of: isFocused) { focused in
                store.isEditingRecordName = focused
                store.keyboardPane = focused ? .value : .records
                if !focused {
                    finishEditing()
                }
            }
            .onSubmit {
                isFocused = false
            }
            .onAppear {
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
            .onDisappear {
                store.isEditingRecordName = false
                finishEditing()
            }
    }

    private func finishEditing() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanName.isEmpty {
            name = store.record(id: record.id)?.name ?? record.name
        } else {
            name = cleanName
            store.updateRecordName(id: record.id, name: cleanName)
        }
        store.flushPendingRecordSave()
    }
}

private struct InlineRecordContentEditor: View {
    @ObservedObject var store: VaultViewModel
    let record: VaultRecord

    @State private var content: String
    @State private var isFocused = false

    init(store: VaultViewModel, record: VaultRecord) {
        self.store = store
        self.record = record
        _content = State(initialValue: record.content)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            InlineContentTextEditor(
                text: $content,
                onFocusChange: handleFocusChange,
                onDelete: {
                    store.deleteRecord(record.id)
                }
            )

            if content.isEmpty {
                Text("开始输入内容…")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(
                cornerRadius: VaultLayout.contentCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: VaultLayout.contentCornerRadius,
                style: .continuous
            )
                .stroke(
                    isFocused
                        ? Color.accentColor.opacity(0.32)
                        : Color(nsColor: .separatorColor).opacity(0.55),
                    lineWidth: 1
                )
        }
        .onChange(of: content) { newValue in
            store.updateRecordContent(id: record.id, content: newValue)
        }
        .onDisappear {
            store.flushPendingRecordSave()
        }
    }

    private func handleFocusChange(_ isFocused: Bool) {
        self.isFocused = isFocused
        store.keyboardPane = isFocused ? .value : .records
        if !isFocused {
            store.flushPendingRecordSave()
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
