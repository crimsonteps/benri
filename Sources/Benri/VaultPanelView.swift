import AppKit
import Foundation
import BenriCore
import SwiftUI

@MainActor
func releasePanelEditingFocus() {
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
    let onPasteRecord: (UUID) -> Void
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
                .benriGlass(cornerRadius: VaultLayout.contentCornerRadius)
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
                .benriSheetBackground()
        }
        .sheet(item: $store.categoryEditor, onDismiss: onEditorDismissed) { context in
            CategoryEditorView(store: store, context: context)
                .benriSheetBackground()
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

                RecordListView(
                    store: store,
                    onPasteRecord: onPasteRecord
                )
                    .frame(width: VaultLayout.recordListWidth)
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: VaultLayout.navigationCornerRadius,
                    style: .continuous
                )
            )
            .benriGlass(cornerRadius: VaultLayout.navigationCornerRadius)

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
                    .benriGlass(cornerRadius: VaultLayout.contentCornerRadius)
            }
        }
        .padding(.horizontal, VaultLayout.windowInset)
        .padding(.top, VaultLayout.windowInset)
        .padding(.bottom, VaultLayout.windowInset * 2)
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
                message: Text("分类中的记录会被移动到另一个可用分类。"),
                primaryButton: .destructive(Text("删除")) {
                    store.deleteCategory(id)
                },
                secondaryButton: .cancel(Text("取消"))
            )
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
