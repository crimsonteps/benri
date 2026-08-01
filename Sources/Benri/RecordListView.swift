import AppKit
import Foundation
import BenriCore
import SwiftUI

struct RecordListView: View {
    @ObservedObject var store: VaultViewModel
    let contextMenuAnchor: RecordContextMenuAnchor
    let onPasteRecord: (UUID) -> Void
    @FocusState private var searchIsFocused: Bool
    @State private var scrollContentFrame = CGRect.null
    @State private var scrollViewportHeight: CGFloat = 0

    private let scrollCoordinateSpace = "recordListScroll"

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .frame(height: BenriTheme.Size.searchHeaderHeight)

            if store.filteredRecords.isEmpty {
                RecordListEmptyView(hasQuery: !store.searchText.isEmpty) {
                    store.beginNewRecord()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            ForEach(store.filteredRecords) { record in
                                RecordRow(
                                    record: record,
                                    contextMenuAnchor: contextMenuAnchor,
                                    categoryName: store.selectedCategoryID == nil
                                        ? store.categoryName(for: record.categoryID)
                                        : nil,
                                    isSelected: store.selectedRecordID == record.id,
                                    isKeyboardActive: store.keyboardPane == .records
                                ) {
                                    releasePanelEditingFocus()
                                    store.selectRecord(record.id)
                                } doubleClickAction: {
                                    releasePanelEditingFocus()
                                    onPasteRecord(record.id)
                                } editAction: {
                                    releasePanelEditingFocus()
                                    store.beginEditingRecord(record.id)
                                } deleteAction: {
                                    store.requestDeleteRecord(record.id)
                                }
                                .id(record.id)
                            }
                        }
                        .background {
                            GeometryReader { content in
                                Color.clear.preference(
                                    key: RecordListContentFramePreferenceKey.self,
                                    value: content.frame(in: .named(scrollCoordinateSpace))
                                )
                            }
                        }
                        .padding(.horizontal, BenriTheme.Spacing.md)
                        .padding(.top, BenriTheme.Spacing.xs)
                        .padding(.bottom, BenriTheme.Spacing.md)
                    }
                    .coordinateSpace(name: scrollCoordinateSpace)
                    .background {
                        GeometryReader { viewport in
                            Color.clear.preference(
                                key: RecordListViewportHeightPreferenceKey.self,
                                value: viewport.size.height
                            )
                        }
                    }
                    .mask {
                        RecordListVisibilityMask(
                            showsTopFade: showsTopMask,
                            showsBottomFade: showsBottomMask
                        )
                    }
                    .overlay(alignment: .top) {
                        if showsTopMask {
                            RecordListEdgeBlur(edge: .top)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if showsBottomMask {
                            RecordListEdgeBlur(edge: .bottom)
                        }
                    }
                    .onPreferenceChange(RecordListContentFramePreferenceKey.self) {
                        scrollContentFrame = $0
                    }
                    .onPreferenceChange(RecordListViewportHeightPreferenceKey.self) {
                        scrollViewportHeight = $0
                    }
                    .onChange(of: store.selectedRecordID) { selectedRecordID in
                        guard let selectedRecordID else { return }
                        proxy.scrollTo(selectedRecordID, anchor: .center)
                    }
                }
            }

        }
        .background(Color.clear)
        .onReceive(NotificationCenter.default.publisher(for: .benriFocusSearch)) { _ in
            searchIsFocused = true
            store.setSearchFocused(true)
            DispatchQueue.main.async {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .benriClearSearchFocus)) { _ in
            searchIsFocused = false
            store.setSearchFocused(false)
        }
        .onChange(of: searchIsFocused) { focused in
            store.setSearchFocused(focused)
        }
        .onChange(of: store.searchText) { _ in
            store.handleFilterChange()
        }
        .onChange(of: store.selectedCategoryID) { _ in
            store.ensureSelection()
        }
    }

    private var showsTopMask: Bool {
        !scrollContentFrame.isNull && scrollContentFrame.minY < -1
    }

    private var showsBottomMask: Bool {
        !scrollContentFrame.isNull && scrollContentFrame.maxY > scrollViewportHeight + 1
    }

    private var searchBar: some View {
        HStack(spacing: BenriTheme.Spacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("搜索记录名称", text: $store.searchText)
                .textFieldStyle(.plain)
                .font(BenriTheme.Typography.search)
                .focused($searchIsFocused)
                .onSubmit {
                    guard let recordID = store.selectedRecordID else { return }
                    onPasteRecord(recordID)
                }

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

            Button(action: store.beginNewRecord) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(
                        width: BenriTheme.Size.floatingButton,
                        height: BenriTheme.Size.floatingButton
                    )
            }
            .benriFloatingCircleButton()
            .help("新建记录 ⌘N")
        }
        .padding(.horizontal, BenriTheme.Spacing.xl)
    }

}

private struct RecordListContentFramePreferenceKey: PreferenceKey {
    static var defaultValue = CGRect.null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct RecordListViewportHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct RecordListVisibilityMask: View {
    let showsTopFade: Bool
    let showsBottomFade: Bool

    private let fadeHeight: CGFloat = 26

    var body: some View {
        VStack(spacing: 0) {
            edgeGradient(isVisible: showsTopFade, edge: .top)
                .frame(height: fadeHeight)

            Color.black

            edgeGradient(isVisible: showsBottomFade, edge: .bottom)
                .frame(height: fadeHeight)
        }
    }

    private func edgeGradient(isVisible: Bool, edge: VerticalEdge) -> LinearGradient {
        LinearGradient(
            colors: isVisible ? [.clear, .black] : [.black, .black],
            startPoint: edge == .top ? .top : .bottom,
            endPoint: edge == .top ? .bottom : .top
        )
    }
}

private struct RecordListEdgeBlur: View {
    let edge: VerticalEdge
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let height: CGFloat = 26

    var body: some View {
        Group {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor).opacity(0.28)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.58), location: 0),
                    .init(color: .black.opacity(0.2), location: 0.58),
                    .init(color: .clear, location: 1)
                ],
                startPoint: edge == .top ? .top : .bottom,
                endPoint: edge == .top ? .bottom : .top
            )
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct RecordRow: View {
    let record: VaultRecord
    let contextMenuAnchor: RecordContextMenuAnchor
    let categoryName: String?
    let isSelected: Bool
    let isKeyboardActive: Bool
    let action: () -> Void
    let doubleClickAction: () -> Void
    let editAction: () -> Void
    let deleteAction: () -> Void

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

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
            HStack(spacing: BenriTheme.Spacing.lg) {
                VStack(alignment: .leading, spacing: BenriTheme.Spacing.xxs) {
                    Text(record.name)
                        .font(BenriTheme.Typography.rowTitle)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(BenriTheme.Typography.rowDetail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BenriTheme.Spacing.md)
            .padding(.vertical, BenriTheme.Spacing.sm)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(
                    cornerRadius: BenriTheme.Radius.row,
                    style: .continuous
                )
                    .fill(rowBackground)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { doubleClickAction() }
        )
        .overlay {
            FixedRecordContextMenu(
                anchor: contextMenuAnchor,
                isSelected: isSelected,
                prepare: action,
                editAction: editAction,
                deleteAction: deleteAction
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected {
            return BenriTheme.Colors.selection(
                for: colorScheme,
                active: isKeyboardActive
            )
        }
        return isHovering
            ? BenriTheme.Colors.rowHover(for: colorScheme)
            : Color.clear
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
