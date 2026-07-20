import AppKit
import QuickVaultCore
import SwiftUI

struct VaultPanelView: View {
    @ObservedObject var store: VaultViewModel
    let onClose: () -> Void

    var body: some View {
        Group {
            if let fatalErrorMessage = store.fatalErrorMessage {
                VaultFailureView(
                    message: fatalErrorMessage,
                    openDataFolder: store.openDataFolder,
                    resetVault: store.requestReset
                )
            } else {
                mainContent
            }
        }
        .frame(width: 820, height: 520)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            if let copyNotice = store.copyNotice {
                Text(copyNotice)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .overlay {
                        Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    }
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .onAppear {
            store.ensureSelection()
        }
        .onMoveCommand { direction in
            switch direction {
            case .up:
                store.moveSelection(-1)
            case .down:
                store.moveSelection(1)
            default:
                break
            }
        }
        .onExitCommand(perform: onClose)
        .sheet(item: $store.recordEditor) { context in
            RecordEditorView(store: store, context: context)
        }
        .sheet(item: $store.categoryEditor) { context in
            CategoryEditorView(store: store, context: context)
        }
        .alert(item: $store.alert) { alert in
            makeAlert(alert)
        }
    }

    private var mainContent: some View {
        HStack(spacing: 0) {
            SidebarView(store: store)
                .frame(width: 154)

            Divider()

            RecordListView(store: store)
                .frame(width: 252)

            Divider()

            RecordDetailView(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
                message: Text("这条记录将从本地保险库中永久删除。"),
                primaryButton: .destructive(Text("删除")) {
                    store.deleteRecord(id)
                },
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
    @ObservedObject var store: VaultViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "lock.square.stack.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("QuickVault")
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 3) {
                    SidebarRow(
                        title: "全部",
                        icon: "square.stack.3d.up.fill",
                        count: store.recordCount(for: nil),
                        isSelected: store.selectedCategoryID == nil
                    ) {
                        store.selectCategory(nil)
                    }

                    ForEach(store.sortedCategories) { category in
                        SidebarRow(
                            title: category.name,
                            icon: iconName(for: category),
                            count: store.recordCount(for: category.id),
                            isSelected: store.selectedCategoryID == category.id
                        ) {
                            store.selectCategory(category.id)
                        }
                        .contextMenu {
                            if !category.isBuiltIn {
                                Button("重命名") {
                                    store.beginRenamingCategory(category.id)
                                }
                                Button("删除", role: .destructive) {
                                    store.requestDeleteCategory(category.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 8)

            Button(action: store.beginNewCategory) {
                Label("新建分类", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(8)
        }
        .background(.thinMaterial)
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
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct RecordListView: View {
    @ObservedObject var store: VaultViewModel
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(12)

            Divider()

            if store.filteredRecords.isEmpty {
                RecordListEmptyView(hasQuery: !store.searchText.isEmpty) {
                    store.beginNewRecord()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.filteredRecords) { record in
                            RecordRow(
                                record: record,
                                categoryName: store.categoryName(for: record.categoryID),
                                isSelected: store.selectedRecordID == record.id
                            ) {
                                store.selectedRecordID = record.id
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .onReceive(NotificationCenter.default.publisher(for: .quickVaultFocusSearch)) { _ in
            searchIsFocused = true
        }
        .onAppear {
            DispatchQueue.main.async {
                searchIsFocused = true
            }
        }
        .onChange(of: store.searchText) { _ in
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
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.9))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            }

            Button(action: store.beginNewRecord) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help("新建记录 ⌘N")
        }
    }
}

private struct RecordRow: View {
    let record: VaultRecord
    let categoryName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(record.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(categoryName)
                    Text("\(record.fields.count) 个字段")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.17) : Color.clear)
            }
        }
        .buttonStyle(.plain)
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

private struct RecordDetailView: View {
    @ObservedObject var store: VaultViewModel
    @State private var revealedFieldIDs = Set<UUID>()

    var body: some View {
        Group {
            if let record = store.selectedRecord {
                recordDetail(record)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.and.text.magnifyingglass")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("选择一条记录查看详情")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.78))
        .onChange(of: store.selectedRecordID) { _ in
            revealedFieldIDs.removeAll()
        }
    }

    private func recordDetail(_ record: VaultRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(record.name)
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(2)
                    Text(store.categoryName(for: record.categoryID))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }

                Spacer()

                Button {
                    store.beginEditingSelectedRecord()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("e", modifiers: .command)
                .help("编辑记录 ⌘E")

                Menu {
                    Button("删除记录", role: .destructive) {
                        store.requestDeleteRecord(record.id)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(20)

            Divider()

            if record.fields.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.and.pencil.and.ellipsis")
                        .font(.system(size: 27, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("这条记录还没有字段")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Button("添加字段") {
                        store.beginEditingSelectedRecord()
                    }
                    .buttonStyle(.link)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(record.fields.sorted(by: { $0.sortOrder < $1.sortOrder })) { field in
                            FieldValueRow(
                                field: field,
                                isRevealed: revealedFieldIDs.contains(field.id),
                                toggleReveal: {
                                    if revealedFieldIDs.contains(field.id) {
                                        revealedFieldIDs.remove(field.id)
                                    } else {
                                        revealedFieldIDs.insert(field.id)
                                    }
                                },
                                copyValue: {
                                    store.copy(field.value, sensitive: field.isSensitive)
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

private struct FieldValueRow: View {
    let field: RecordField
    let isRevealed: Bool
    let toggleReveal: () -> Void
    let copyValue: () -> Void

    private var displayedValue: String {
        if field.isSensitive && !isRevealed {
            return String(repeating: "•", count: max(8, min(field.value.count, 16)))
        }
        return field.value.isEmpty ? "未填写" : field.value
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(field.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(displayedValue)
                    .font(.system(size: 13, design: field.isSensitive && !isRevealed ? .monospaced : .default))
                    .foregroundStyle(field.value.isEmpty ? .secondary : .primary)
                    .lineLimit(field.isSensitive ? 1 : 4)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            if field.isSensitive {
                Button(action: toggleReveal) {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help(isRevealed ? "隐藏内容" : "显示内容")
            }

            Button(action: copyValue) {
                Image(systemName: "doc.on.doc")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("复制")
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
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
