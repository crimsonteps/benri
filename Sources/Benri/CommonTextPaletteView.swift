import BenriCore
import SwiftUI

struct CommonTextPaletteView: View {
    @ObservedObject var store: VaultViewModel
    let onPaste: (UUID) -> Void
    let onActions: (VaultRecord) -> Void

    var body: some View {
        HStack(spacing: 0) {
            recordList
                .frame(width: 330)

            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 1)
                .padding(.vertical, 10)

            recordPreview
        }
    }

    private var recordList: some View {
        Group {
            if store.filteredRecords.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 28, weight: .light))
                    Text(store.searchText.isEmpty ? "还没有常用文本" : "没有匹配的常用文本")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(store.filteredRecords) { record in
                                CommonTextRow(
                                    record: record,
                                    selected: record.id == store.selectedRecordID
                                )
                                .id(record.id)
                                .contentShape(Rectangle())
                                .onTapGesture { store.selectRecord(record.id) }
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        store.selectRecord(record.id)
                                        onPaste(record.id)
                                    }
                                )
                                .background {
                                    RightClickAction {
                                        store.selectRecord(record.id)
                                        onActions(record)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: store.selectedRecordID) { id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recordPreview: some View {
        if let record = store.selectedRecord {
            ScrollView {
                Text(record.content.isEmpty ? "暂无内容" : record.content)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(
                        record.content.isEmpty
                            ? Color.secondary
                            : Color.primary.opacity(0.88)
                    )
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 30, weight: .light))
                Text("选择一条常用文本以预览")
                    .font(.system(size: 13))
            }
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct CommonTextRow: View {
    let record: VaultRecord
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.10))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "doc.text")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(record.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .lineLimit(1)
                Text(record.content.isEmpty ? "暂无内容" : record.content)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    selected
                        ? Color.primary.opacity(0.16)
                        : hovering ? Color.primary.opacity(0.07) : Color.clear
                )
        )
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
