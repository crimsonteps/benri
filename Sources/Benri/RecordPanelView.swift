import Foundation
import BenriCore
import SwiftUI

struct RecordPanelView: View {
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                InlineRecordNameEditor(store: store, record: record)
                    .id(record.id)

                Spacer(minLength: 8)

                InlineRecordCategoryEditor(store: store, record: record)

                Button {
                    store.copy(record.content)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .frame(
                            width: BenriTheme.Size.floatingButton,
                            height: BenriTheme.Size.floatingButton
                        )
                }
                .benriFloatingCircleButton()
                .disabled(record.content.isEmpty)
                .help("复制内容")
            }
            .padding(.horizontal, BenriTheme.Spacing.xl)
            .frame(height: BenriTheme.Size.searchHeaderHeight)

            InlineRecordContentEditor(store: store, record: record)
                .id(record.id)
                .padding([.horizontal, .bottom], BenriTheme.Spacing.md)
        }
    }
}

private struct InlineRecordCategoryEditor: View {
    @ObservedObject var store: VaultViewModel
    let record: VaultRecord

    var body: some View {
        Picker("分类", selection: categorySelection) {
            ForEach(store.sortedCategories) { category in
                Label(
                    category.name,
                    systemImage: CategoryIconCatalog.iconName(for: category)
                )
                .tag(category.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: 118)
        .help("更改分类")
    }

    private var categorySelection: Binding<UUID> {
        Binding(
            get: { record.categoryID },
            set: { categoryID in
                store.updateRecordCategory(id: record.id, categoryID: categoryID)
            }
        )
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
            .font(BenriTheme.Typography.preview)
            .lineSpacing(3)
            .foregroundStyle(content.isEmpty ? Color.secondary : Color.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(BenriTheme.Spacing.xxl)
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
            .font(.system(size: 18, weight: .medium))
            .lineLimit(1)
            .focused($isFocused)
            .onChange(of: name) { newValue in
                store.updateRecordName(id: record.id, name: newValue)
            }
            .onChange(of: isFocused) { focused in
                store.isEditingRecordName = focused
                store.activateRecordEditingFocus()
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
    @Environment(\.colorScheme) private var colorScheme

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
                    store.requestDeleteRecord(record.id)
                }
            )

            if content.isEmpty {
                Text("开始输入内容…")
                    .font(BenriTheme.Typography.preview)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            BenriTheme.Colors.cardFill(for: colorScheme),
            in: RoundedRectangle(
                cornerRadius: BenriTheme.Radius.card,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: BenriTheme.Radius.card,
                style: .continuous
            )
                .stroke(
                    isFocused
                        ? Color.accentColor.opacity(0.30)
                        : BenriTheme.Colors.border(for: colorScheme),
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
        store.activateRecordEditingFocus()
        if !isFocused {
            store.flushPendingRecordSave()
        }
    }
}
