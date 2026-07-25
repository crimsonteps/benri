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
