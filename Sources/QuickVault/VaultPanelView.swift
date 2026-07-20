import AppKit
import QuickVaultCore
import SwiftUI

struct VaultPanelView: View {
    @ObservedObject var store: VaultViewModel
    @ObservedObject var settings: AppSettings
    let openSettings: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sidebarExpanded = false

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
        .frame(minWidth: 820, minHeight: 520)
        .background {
            Color.clear
                .quickVaultGlass(cornerRadius: 0)
                .ignoresSafeArea()
        }
        .onAppear {
            store.ensureSelection()
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
        .preferredColorScheme(settings.appearanceMode.colorScheme)
    }

    private var mainContent: some View {
        HStack(spacing: 0) {
            SidebarView(
                store: store,
                isExpanded: sidebarExpanded,
                toggleExpanded: {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        sidebarExpanded.toggle()
                    }
                },
                openSettings: openSettings
            )
            .frame(width: sidebarExpanded ? 156 : 56)
            .keyboardPaneFocus(store.keyboardPane == .categories)

            Divider().opacity(0.45)

            RecordListView(
                store: store,
                hidePreviews: settings.hideRecordPreviews
            )
                .frame(width: 264)
                .keyboardPaneFocus(store.keyboardPane == .records)

            Divider().opacity(0.45)

            RecordDetailView(
                store: store,
                valueOnly: store.keyboardPane == .value
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .keyboardPaneFocus(store.keyboardPane == .value)
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
    let isExpanded: Bool
    let toggleExpanded: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 4) {
                    SidebarRow(
                        title: "全部",
                        icon: "square.stack.3d.up.fill",
                        count: store.recordCount(for: nil),
                        isSelected: store.selectedCategoryID == nil,
                        isExpanded: isExpanded
                    ) {
                        store.selectCategory(nil)
                    }

                    ForEach(store.sortedCategories) { category in
                        SidebarRow(
                            title: category.name,
                            icon: iconName(for: category),
                            count: store.recordCount(for: category.id),
                            isSelected: store.selectedCategoryID == category.id,
                            isExpanded: isExpanded
                        ) {
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
                    }
                }
                .padding(.horizontal, 7)
            }

            Spacer(minLength: 8)

            bottomActions
        }
        .background(Color.primary.opacity(0.025))
    }

    @ViewBuilder
    private var bottomActions: some View {
        Group {
            if isExpanded {
                HStack(spacing: 3) {
                    newCategoryButton(showLabel: true)
                    settingsButton
                }
            } else {
                VStack(spacing: 2) {
                    newCategoryButton(showLabel: false)
                    settingsButton
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(7)
    }

    private func newCategoryButton(showLabel: Bool) -> some View {
        Button(action: store.beginNewCategory) {
            Group {
                if showLabel {
                    Label("新建", systemImage: "plus")
                } else {
                    Image(systemName: "plus")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
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
        HStack(spacing: 8) {
            Button(action: toggleExpanded) {
                Image(systemName: isExpanded ? "sidebar.left" : "lock.square.stack.fill")
                    .font(.system(size: isExpanded ? 14 : 18, weight: .semibold))
                    .foregroundStyle(isExpanded ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "折叠分类栏" : "展开分类栏")

            if isExpanded {
                Text("valuet")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, isExpanded ? 10 : 13)
        .padding(.top, 15)
        .padding(.bottom, 12)
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
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
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
            .frame(height: 34)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .help("\(title)，\(count) 条记录")
    }
}

private struct RecordListView: View {
    @ObservedObject var store: VaultViewModel
    let hidePreviews: Bool
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(12)

            Divider().opacity(0.45)

            if store.filteredRecords.isEmpty {
                RecordListEmptyView(hasQuery: !store.searchText.isEmpty) {
                    store.beginNewRecord()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(store.filteredRecords) { record in
                            RecordRow(
                                record: record,
                                categoryName: store.categoryName(for: record.categoryID),
                                showsPreview: !hidePreviews,
                                isSelected: store.selectedRecordID == record.id
                            ) {
                                store.keyboardPane = .records
                                store.selectedRecordID = record.id
                            } deleteAction: {
                                store.deleteRecord(record.id)
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(Color.primary.opacity(0.015))
        .onReceive(NotificationCenter.default.publisher(for: .quickVaultFocusSearch)) { _ in
            searchIsFocused = true
        }
        .onAppear {
            DispatchQueue.main.async {
                searchIsFocused = true
            }
        }
        .onChange(of: store.searchText) { _ in
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
            .frame(height: 33)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            }

            Button(action: store.beginNewRecord) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 31, height: 31)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
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
    let showsPreview: Bool
    let isSelected: Bool
    let action: () -> Void
    let deleteAction: () -> Void

    private var preview: String {
        let firstLine = record.content
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        return firstLine ?? "暂无内容"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(record.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 7) {
                    Text(categoryName)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                    if showsPreview {
                        Text(preview)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.19) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("删除记录", role: .destructive, action: deleteAction)
        }
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
    let valueOnly: Bool

    var body: some View {
        Group {
            if let record = store.selectedRecord {
                if valueOnly {
                    recordValue(record)
                        .contextMenu {
                            deleteRecordButton(record)
                        }
                } else {
                    recordDetail(record)
                        .contextMenu {
                            deleteRecordButton(record)
                        }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.and.text.magnifyingglass")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("选择一条记录查看内容")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.clear)
    }

    private func recordValue(_ record: VaultRecord) -> some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                Text(record.content.isEmpty ? "暂无内容" : record.content)
                    .font(.system(size: 15))
                    .lineSpacing(6)
                    .foregroundStyle(record.content.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .contextMenu {
                        deleteRecordButton(record)
                    }
                    .padding(24)
                    .padding(.trailing, 36)
            }

            Button {
                store.copy(record.content)
            } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(record.content.isEmpty)
            .help("复制当前值")
            .padding(16)
        }
    }

    private func recordDetail(_ record: VaultRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
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

            }
            .padding(20)

            Divider().opacity(0.45)

            if record.content.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("这条记录还没有内容")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("内容")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                store.copy(record.content)
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            .help("复制全部内容")
                        }

                        Text(record.content)
                            .font(.system(size: 14))
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .contextMenu {
                                deleteRecordButton(record)
                            }
                    }
                    .padding(16)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .padding(16)
                }
            }
        }
    }

    private func deleteRecordButton(_ record: VaultRecord) -> some View {
        Button("删除记录", role: .destructive) {
            store.deleteRecord(record.id)
        }
    }
}

private extension View {
    func keyboardPaneFocus(_ isActive: Bool) -> some View {
        overlay(alignment: .top) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .allowsHitTesting(false)
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
