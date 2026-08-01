import Foundation
import BenriCore
import SwiftUI

struct SidebarView: View {
    private enum ScrollTarget: Hashable {
        case all
        case category(UUID)
    }

    @ObservedObject var store: VaultViewModel
    let isExpanded: Bool
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: BenriTheme.Size.searchHeaderHeight)
                .accessibilityHidden(true)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: BenriTheme.Spacing.xxs) {
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
                                icon: CategoryIconCatalog.iconName(for: category),
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
                                Button("编辑分类") {
                                    store.beginEditingCategory(category.id)
                                }
                                Button("删除分类", role: .destructive) {
                                    store.requestDeleteCategory(category.id)
                                }
                                .disabled(store.sortedCategories.count <= 1)
                            }
                            .id(ScrollTarget.category(category.id))
                        }
                    }
                    .padding(.horizontal, BenriTheme.Spacing.md)
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
                VStack(spacing: BenriTheme.Spacing.sm) {
                    newCategoryButton
                    settingsButton
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(BenriTheme.Spacing.md)
    }

    private var newCategoryButton: some View {
        Button(action: store.beginNewCategory) {
            Image(systemName: "plus")
                .frame(
                    width: BenriTheme.Size.floatingButton,
                    height: BenriTheme.Size.floatingButton
                )
        }
        .benriFloatingCircleButton()
        .help("新建分类")
    }

    private var settingsButton: some View {
        Button(action: openSettings) {
            Image(systemName: "gearshape")
                .frame(
                    width: BenriTheme.Size.floatingButton,
                    height: BenriTheme.Size.floatingButton
                )
        }
        .benriFloatingCircleButton()
        .help("设置 ⌘,")
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
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
            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
            .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
            .padding(.horizontal, isExpanded ? 9 : 0)
            .frame(height: 38)
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
